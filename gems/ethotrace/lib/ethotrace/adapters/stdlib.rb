# frozen_string_literal: true

require "securerandom"

module Ethotrace
  # core 内蔵アダプタの名前空間。
  module Adapters
    # stdlib のチョークポイントを計装し、Requirements チャネルへエフェクトを
    # 記録する core 内蔵アダプタ。
    #
    # 本 feature では**読み取り系**を扱う: `env.read`(ENV)/ `time.read`
    # (Time・Process.clock_gettime)/ `random.read`(Random・SecureRandom)。
    # 書き込み系(env.write / io / process.exec / stdio / global)は後続 feature。
    #
    # dogfooding 原則: 記録は必ず公開 API({Instrumenter#record_effect})経由で行う。
    # フックの prepend はプロセス内で 1 回だけ(冪等)。prepend は外せないため、
    # {#uninstall} は instrumenter 参照を外して**無効化**する(以後フックは素通し)。
    #
    # 機微情報ポリシー(docs/schema.md §6): ENV は **key のみ**記録し value は残さない。
    class Stdlib < Adapter
      # `random.read` として計装する SecureRandom のメソッド群。
      SECURE_RANDOM_METHODS = %i[hex base64 urlsafe_base64 uuid random_number random_bytes alphanumeric].freeze

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

        private

        def install_hooks
          hook_env
          hook_simple(Time.singleton_class, %i[now], "time.read")
          hook_simple(Process.singleton_class, %i[clock_gettime], "time.read")
          hook_simple(Random.singleton_class, %i[rand], "random.read")
          hook_simple(SecureRandom.singleton_class, SECURE_RANDOM_METHODS, "random.read")
        end

        # ENV の読み取り。key のみ detail に載せ、value は記録しない。
        def hook_env
          mod = Module.new
          %i[[] fetch].each do |meth|
            mod.define_method(meth) do |key, *args, **kwargs, &block|
              Stdlib.record("env.read", write: false, key: key)
              super(key, *args, **kwargs, &block)
            end
          end
          ENV.singleton_class.prepend(mod)
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
