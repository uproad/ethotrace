# frozen_string_literal: true

require "securerandom"

module Ethotrace
  # core 内蔵アダプタの名前空間。
  module Adapters
    # stdlib のチョークポイントを計装し、Requirements チャネルへエフェクトを
    # 記録する core 内蔵アダプタ。
    #
    # 計装するチョークポイント:
    # - `env.read` / `env.write`(ENV)
    # - `time.read`(Time・Process.clock_gettime)
    # - `random.read`(Random・SecureRandom)
    # - `io.read` / `io.write`(File.read/write/open/binread/binwrite)
    # - `process.exec`(Kernel#system / backtick / spawn / exec、Process.spawn)
    #
    # `stdio.write`($stdout/$stderr 差し替えへの頑健対応が必要)と `global.write`
    # (グローバルごとに `trace_var` 登録が必要で blanket フックに馴染まない)は
    # 後続で扱う。グローバル変数の**読み取り**は Ruby の仕組み上フック不可。
    #
    # dogfooding 原則: 記録は必ず公開 API({Instrumenter#record_effect})経由で行う。
    # フックの prepend はプロセス内で 1 回だけ(冪等)。prepend は外せないため、
    # {#uninstall} は instrumenter 参照を外して**無効化**する(以後フックは素通し)。
    #
    # 機微情報ポリシー(docs/schema.md §6): ENV は **key のみ**記録し value は残さない。
    #
    # 行数は計装するチョークポイント数に比例して大きくなる(各フック生成は小さく
    # 凝集している)ため、行数のためだけに分散させず ClassLength を緩める。
    class Stdlib < Adapter # rubocop:disable Metrics/ClassLength
      # `random.read` として計装する SecureRandom のメソッド群。
      SECURE_RANDOM_METHODS = %i[hex base64 urlsafe_base64 uuid random_number random_bytes alphanumeric].freeze
      # File の read/write 系メソッド → [語彙, mode 表記, write?]。
      FILE_IO_METHODS = {
        read: ["io.read", "r", false], binread: ["io.read", "rb", false],
        write: ["io.write", "w", true], binwrite: ["io.write", "wb", true]
      }.freeze

      @instrumenter = nil
      @hooked = false

      class << self
        # フックから呼ばれる記録の入口。現在の instrumenter(公開 API)へ委譲する。
        # 無効時(instrumenter 未設定)は何もしない。
        def record(kind, write:, **detail)
          @instrumenter&.record_effect(kind, write: write, **detail)
        end

        # フックを(未設置なら)設置し、記録先の instrumenter を有効化する。
        def enable(instrumenter)
          install_hooks unless @hooked
          @hooked = true
          @instrumenter = instrumenter
        end

        # 記録を無効化する(prepend 済みフックは素通しになる)。
        def disable
          @instrumenter = nil
        end

        # process.exec のコマンドをマスクする: プログラム名のみ残し、引数は捨てる
        # (引数に機微情報が載りやすいため)。先頭の env ハッシュは読み飛ばす。
        def mask_command(args)
          list = args.dup
          list.shift if list.first.is_a?(Hash)
          first = list.first
          return "?" if first.nil?

          program = first.is_a?(Array) ? first.first : first
          program.to_s.split(/\s+/).first || "?"
        end

        # File.open の mode から [語彙, mode 表記, write?] を判定する。
        # 文字列 mode に w/a/+ を含めば書き込み、それ以外(整数 mode・省略含む)は読み取り扱い。
        def classify_open(mode)
          str = mode.is_a?(String) ? mode : nil
          return ["io.write", str, true] if str&.match?(/[wa+]/)

          ["io.read", str || "r", false]
        end

        private

        def install_hooks
          hook_env
          hook_io
          hook_process
          hook_simple(Time.singleton_class, %i[now], "time.read")
          hook_simple(Process.singleton_class, %i[clock_gettime], "time.read")
          hook_simple(Random.singleton_class, %i[rand], "random.read")
          hook_simple(SecureRandom.singleton_class, SECURE_RANDOM_METHODS, "random.read")
        end

        # ENV の読み書き。key のみ detail に載せ、value は記録しない。
        def hook_env
          mod = Module.new
          define_keyed(mod, %i[[] fetch], "env.read", write: false)
          define_keyed(mod, %i[[]= store delete], "env.write", write: true)
          ENV.singleton_class.prepend(mod)
        end

        # 第 1 引数を key として記録するメソッド群を定義する(ENV 用)。
        def define_keyed(mod, methods, kind, write:)
          methods.each do |meth|
            mod.define_method(meth) do |key, *args, **kwargs, &block|
              Stdlib.record(kind, write: write, key: key)
              super(key, *args, **kwargs, &block)
            end
          end
        end

        # File の read/write/open。detail に path と mode を載せる。
        def hook_io
          mod = Module.new
          FILE_IO_METHODS.each do |meth, (kind, mode, write)|
            mod.define_method(meth) do |*args, **kwargs, &block|
              Stdlib.record(kind, write: write, path: PathNormalizer.relativize(args.first.to_s), mode: mode)
              super(*args, **kwargs, &block)
            end
          end
          define_io_open(mod)
          File.singleton_class.prepend(mod)
        end

        # File.open は mode から読み書きを判定する。
        def define_io_open(mod)
          mod.define_method(:open) do |*args, **kwargs, &block|
            kind, mode, write = Stdlib.classify_open(args[1])
            Stdlib.record(kind, write: write, path: PathNormalizer.relativize(args.first.to_s), mode: mode)
            super(*args, **kwargs, &block)
          end
        end

        # 外部プロセス起動。コマンドはマスクして記録する。
        def hook_process
          hook_kernel_exec
          hook_process_spawn
        end

        # Kernel#system / spawn / exec / backtick。private を保つ。
        def hook_kernel_exec
          mod = Module.new
          %i[system spawn exec].each do |meth|
            mod.define_method(meth) do |*args, **kwargs, &block|
              Stdlib.record("process.exec", write: true, command: Stdlib.mask_command(args))
              super(*args, **kwargs, &block)
            end
          end
          define_backtick(mod)
          mod.send(:private, :system, :spawn, :exec, :`)
          Kernel.prepend(mod)
        end

        # Kernel#`(バッククォート)。
        def define_backtick(mod)
          mod.define_method(:`) do |command|
            Stdlib.record("process.exec", write: true, command: Stdlib.mask_command([command]))
            super(command)
          end
        end

        # Process.spawn。
        def hook_process_spawn
          mod = Module.new
          mod.define_method(:spawn) do |*args, **kwargs, &block|
            Stdlib.record("process.exec", write: true, command: Stdlib.mask_command(args))
            super(*args, **kwargs, &block)
          end
          Process.singleton_class.prepend(mod)
        end

        # detail を持たない読み取り系チョークポイントを一括で計装する。
        def hook_simple(singleton, methods, kind)
          mod = Module.new
          methods.each do |meth|
            mod.define_method(meth) do |*args, **kwargs, &block|
              Stdlib.record(kind, write: false)
              super(*args, **kwargs, &block)
            end
          end
          singleton.prepend(mod)
        end
      end

      # session レコード(docs/schema.md §3 の `adapters`)用の短い名前。
      def name
        "stdlib"
      end

      def install(instrumenter)
        self.class.enable(instrumenter)
      end

      def uninstall(_instrumenter)
        self.class.disable
      end
    end
  end
end
