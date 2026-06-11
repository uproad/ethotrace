# frozen_string_literal: true

require "optparse"

module Ethotrace
  module CLI
    # `ethotrace view` サブコマンド。JSONL を読み、表示用にマージして、
    # サマリ(既定)または 1 メソッドの詳細(--index / --method)を描画する。
    class ViewCommand
      def initialize(out: $stdout, err: $stderr)
        @out = out
        @err = err
      end

      # @return [Integer] 終了ステータス。
      def run(argv)
        options = {}
        files = parse(argv, options)
        return usage_error("no input files") if files.empty?

        observations = Aggregator.call(Reader.new(warn_io: @err).read(files).observations)
        return empty_notice if observations.empty?

        color = Color.new(enabled: color_enabled?(options))
        renderer = Renderer.new(out: @out, color: color)
        render(observations, options, renderer)
      rescue OptionParser::ParseError => e
        usage_error(e.message)
      end

      private

      def parse(argv, options)
        parser = build_parser(options)
        files = parser.parse(argv)
        @out.puts(parser) if options[:help]
        files
      end

      def build_parser(options)
        OptionParser.new do |o|
          o.banner = "Usage: ethotrace view [options] <file.jsonl>..."
          o.on("-m", "--method NAME", "show full detail for the method (Owner#name)") { |v| options[:method] = v }
          o.on("-i", "--index N", Integer, "show full detail for the summary index N") { |v| options[:index] = v }
          o.on("--[no-]color", "force color output on or off") { |v| options[:color] = v }
          o.on("-h", "--help", "show this help") { options[:help] = true }
        end
      end

      def render(observations, options, renderer)
        return 0 if options[:help]

        if options[:index]
          render_by_index(observations, options[:index], renderer)
        elsif options[:method]
          render_by_method(observations, options[:method], renderer)
        else
          renderer.summary(observations)
          0
        end
      end

      def render_by_index(observations, index, renderer)
        observation = observations[index - 1] if index.positive?
        return usage_error("index out of range: #{index} (1..#{observations.size})") unless observation

        renderer.detail(observation)
        0
      end

      def render_by_method(observations, name, renderer)
        matches = observations.select { |observation| observation.id == name }
        matches = observations.select { |observation| observation.id.include?(name) } if matches.empty?
        return usage_error("no method matching: #{name}") if matches.empty?

        matches.each_with_index do |observation, i|
          @out.puts if i.positive?
          renderer.detail(observation)
        end
        0
      end

      def color_enabled?(options)
        options.fetch(:color) { Color.enabled_for?(@out) }
      end

      def empty_notice
        @out.puts("no observations found")
        0
      end

      def usage_error(message)
        @err.puts("ethotrace view: #{message}")
        1
      end
    end
  end
end
