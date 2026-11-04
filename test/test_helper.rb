# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "fast_sheet"
require "fast_xlsx"
require "tmpdir"

require "minitest/autorun"

module SheetHelpers
  FIXTURES = File.expand_path("fixtures", __dir__)

  def fixture(name) = File.join(FIXTURES, name)

  # Writes `content` (bytes) to a file named `name` in a fresh temp dir.
  def temp_file(name, content)
    @dir ||= Dir.mktmpdir
    File.binwrite(File.join(@dir, name), content).then { File.join(@dir, name) }
  end

  # An xlsx built with fast_xlsx; the block gets the workbook.
  def xlsx(name = "book.xlsx")
    workbook = FastXlsx::Workbook.new
    yield workbook
    temp_file(name, workbook.to_xlsx)
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end
end
