# frozen_string_literal: true

module Ethotrace
  # 観測パス(定義位置 `site` / io エフェクトのファイルパス)を可搬な形へ正規化する。
  #
  # `Method#source_location` や File 系 API は絶対パスを返すため、そのまま記録すると
  # 観測環境のホームディレクトリやマシン固有パスが JSONL に混入し、機微情報の漏洩
  # (設計資料 §6)と観測環境間での無意味な差分を招く。基準ディレクトリ(`Ethotrace.base_dir`、
  # 既定はプロセスの作業ディレクトリ = 観測対象プロジェクトのルート)配下のパスは、
  # そこからの相対パスへ畳む。基準の外(third-party gem / stdlib / tmp 等の外部資源)は
  # 相対化しても可搬にならないため絶対のまま残す。
  #
  # スキーマ(`docs/schema.md` §4.2 / §5)が要求する「リポジトリ相対に正規化された
  # パス」を満たすのはこの層であり、出力前に必ず通す。
  module PathNormalizer
    module_function

    # @param path [String, nil] 正規化対象のパス(絶対・相対いずれも可)。
    # @param base [String, nil] 基準ディレクトリ。nil なら正規化しない。
    # @return [String, nil] base 配下なら base からの相対パス、base 外なら元のパス。
    def relativize(path, base: Ethotrace.base_dir)
      return path if path.nil? || base.nil?

      absolute = File.expand_path(path)
      prefix = File.join(File.expand_path(base), "")
      absolute.start_with?(prefix) ? absolute.delete_prefix(prefix) : path
    end
  end
end
