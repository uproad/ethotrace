# frozen_string_literal: true

module Ethotrace
  module CLI
    # 端末向けの最小限の ANSI 装飾。依存を増やさないため自前で持つ。
    # 無効時(非 TTY / NO_COLOR / --no-color)は素の文字列を返す。
    class Color
      CODES = {
        bold: 1, dim: 2,
        red: 31, green: 32, yellow: 33, blue: 34, magenta: 35, cyan: 36, gray: 90
      }.freeze

      # 出力先と環境から色付けの既定可否を判定する。
      def self.enabled_for?(io)
        ENV["NO_COLOR"].nil? && io.respond_to?(:tty?) && io.tty?
      end

      def initialize(enabled:)
        @enabled = enabled
      end

      # text を styles(:red, :bold ...)で装飾する。無効時は素通し。
      def paint(text, *styles)
        return text.to_s if !@enabled || styles.empty?

        codes = styles.map { |style| CODES.fetch(style) }.join(";")
        "\e[#{codes}m#{text}\e[0m"
      end
    end
  end
end
