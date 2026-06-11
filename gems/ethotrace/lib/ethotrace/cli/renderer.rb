# frozen_string_literal: true

module Ethotrace
  module CLI
    # マージ済み観測を端末向けに描画する。サマリ(一覧)と詳細(全情報)の
    # 2 段階を提供する。最終形を見据え、M1 で空の params / requirements も
    # セクション枠を必ず出す。
    class Renderer
      NONE = "(none observed)"

      def initialize(out:, color:)
        @out = out
        @color = color
      end

      # サマリ一覧。各メソッドを 1 行に要約し、先頭に 1 始まりの index を振る。
      # 詳細は `--index N` / `--method NAME` で開く。
      def summary(observations)
        @out.puts(header(observations))
        @out.puts

        width = observations.map { |observation| observation.id.length }.max || 0
        observations.each_with_index do |observation, i|
          @out.puts(summary_line(i + 1, observation, width))
        end

        @out.puts
        @out.puts(@color.paint('詳細: ethotrace view <files> -i N  (または -m "Owner#name")', :dim))
      end

      # 1 メソッドの全情報。三チャネル + 引数プロトコルのセクションを常に出す。
      def detail(observation)
        render_heading(observation)
        render_return(observation)
        render_params(observation)
        render_errors(observation)
        render_requirements(observation)
      end

      private

      def render_heading(observation)
        kind = @color.paint("(#{observation.kind})", :dim)
        @out.puts("#{@color.paint(observation.id, :bold)}  #{kind}")
        @out.puts("  site     : #{site_text(observation.site)}")
        @out.puts("  samples  : #{observation.samples}")
        @out.puts("  sessions : #{list_or_none(observation.sessions)}")
        @out.puts
      end

      def list_or_none(items)
        items.empty? ? NONE : items.join(", ")
      end

      def header(observations)
        sessions = observations.flat_map(&:sessions).uniq.size
        samples = observations.sum(&:samples)
        @color.paint("#{observations.size} methods · #{sessions} sessions · #{samples} samples", :bold)
      end

      def summary_line(index, observation, width)
        idx = @color.paint(format("[%d]", index), :gray)
        id = @color.paint(observation.id.ljust(width), :bold)
        ret = "return: #{observation.return_summary || @color.paint("-", :dim)}"
        errors = paint_error_count(observation.error_type_count)
        "#{idx} #{id}  #{ret}  args: #{observation.protocol_count}  #{errors}  samples: #{observation.samples}"
      end

      def paint_error_count(count)
        text = "errors: #{count}"
        count.positive? ? @color.paint(text, :red) : text
      end

      # title 見出しを出し、items があればブロックで描画、空なら NONE を出す。
      def section(title, color, empty:)
        @out.puts("  #{@color.paint(title, color)}")
        if empty
          @out.puts("    #{NONE}")
        else
          yield
        end
        @out.puts
      end

      def render_return(observation)
        section("return (Success):", :green, empty: observation.return_classes.empty?) do
          observation.return_classes.each { |klass| @out.puts("    #{klass}") }
        end
      end

      def render_params(observation)
        section("args (protocol):", :cyan, empty: observation.params.empty?) do
          observation.params.each { |param| render_param(param) }
        end
      end

      def render_param(param)
        label = param[:name] || "(positional)"
        seen = param[:classes_seen].empty? ? "-" : param[:classes_seen].join(", ")
        @out.puts("    [#{param[:position]}] #{label} : #{seen}")
        param[:protocol].each do |entry|
          block = entry[:block] ? ", block" : ""
          @out.puts("        #{entry[:name]}(arity #{entry[:arity]}#{block})")
        end
      end

      def render_errors(observation)
        section("errors (Error):", :red, empty: observation.errors.empty?) do
          observation.errors.each { |error| @out.puts("    #{error_text(error)}") }
        end
      end

      def error_text(error)
        tag = error[:origin] == "inherited" ? "inherited from #{error[:from]}" : error[:origin]
        "#{error[:class]}  [#{tag}]"
      end

      def render_requirements(observation)
        section("requirements:", :yellow, empty: observation.requirements.empty?) do
          observation.requirements.each { |requirement| @out.puts("    #{requirement_text(requirement)}") }
        end
      end

      def requirement_text(requirement)
        mode = requirement[:write] ? "write" : "read"
        scope = requirement[:direct] ? "direct" : "inherited from #{requirement[:from]}"
        "#{requirement[:kind]}  [#{mode}, #{scope}]  #{requirement[:detail].to_json}"
      end

      def site_text(site)
        site ? "#{site[:path]}:#{site[:line]}" : NONE
      end
    end
  end
end
