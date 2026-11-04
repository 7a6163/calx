# frozen_string_literal: true

require "test_helper"
require "pathname"
require "tempfile"

class TestFiles < Minitest::Test
  include SheetHelpers

  def test_pathname_and_file
    path = temp_file("a.csv", "a\n")

    assert_equal [%w[a]], FastSheet.read(Pathname(path))
    File.open(path) { |f| assert_equal [%w[a]], FastSheet.read(f) }
  end

  def test_format_from_the_extension_ignores_case
    assert_equal [%w[a]], FastSheet.read(temp_file("A.CSV", "a\n"))
  end

  def test_format_option_for_files_without_an_extension
    Tempfile.create("upload") do |f|
      f.write(FastXlsx::Workbook.new.tap { |wb| wb.add_worksheet << ["x"] }.to_xlsx)
      f.close

      assert_raises(ArgumentError) { FastSheet.read(f.path) }
      assert_equal [["x"]], FastSheet.read(f.path, format: :xlsx)
    end
  end

  def test_unknown_format
    path = temp_file("a.csv", "a\n")

    assert_raises(ArgumentError) { FastSheet.read(path, format: :numbers) }
    assert_raises(ArgumentError) { FastSheet.read(temp_file("a.txt", "a\n")) }
  end

  def test_missing_file
    assert_raises(Errno::ENOENT) { FastSheet.read("nope.csv") }
    assert_raises(Errno::ENOENT) { FastSheet.sheet_names("nope.xlsx") }
  end

  def test_path_type
    assert_raises(TypeError) { FastSheet.read(42) }
  end

  def test_corrupt_spreadsheet
    path = temp_file("bad.xlsx", "not a zip")

    assert_raises(FastSheet::Error) { FastSheet.read(path) }
    assert_raises(FastSheet::Error) { FastSheet.sheet_names(path) }
    assert_raises(FastSheet::Error) { FastSheet.read(path, format: :xls) }
    assert_raises(FastSheet::Error) { FastSheet.read(path, format: :xlsb) }
    assert_raises(FastSheet::Error) { FastSheet.read(path, format: :ods) }
  end
end
