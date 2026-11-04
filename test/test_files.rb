# frozen_string_literal: true

require "test_helper"
require "pathname"
require "tempfile"

class TestFiles < Minitest::Test
  include SheetHelpers

  def test_pathname_and_file
    path = temp_file("a.csv", "a\n")

    assert_equal [%w[a]], Calx.read(Pathname(path))
    File.open(path) { |f| assert_equal [%w[a]], Calx.read(f) }
  end

  def test_format_from_the_extension_ignores_case
    assert_equal [%w[a]], Calx.read(temp_file("A.CSV", "a\n"))
  end

  def test_format_option_for_files_without_an_extension
    Tempfile.create("upload") do |f|
      f.write(FastXlsx::Workbook.new.tap { |wb| wb.add_worksheet << ["x"] }.to_xlsx)
      f.close

      assert_raises(ArgumentError) { Calx.read(f.path) }
      assert_equal [["x"]], Calx.read(f.path, format: :xlsx)
    end
  end

  def test_unknown_format
    path = temp_file("a.csv", "a\n")

    assert_raises(ArgumentError) { Calx.read(path, format: :numbers) }
    assert_raises(ArgumentError) { Calx.read(temp_file("a.txt", "a\n")) }
  end

  def test_missing_file
    assert_raises(Errno::ENOENT) { Calx.read("nope.csv") }
    assert_raises(Errno::ENOENT) { Calx.sheet_names("nope.xlsx") }
  end

  def test_path_type
    assert_raises(TypeError) { Calx.read(42) }
  end

  def test_corrupt_spreadsheet
    path = temp_file("bad.xlsx", "not a zip")

    assert_raises(Calx::Error) { Calx.read(path) }
    assert_raises(Calx::Error) { Calx.sheet_names(path) }
    assert_raises(Calx::Error) { Calx.read(path, format: :xls) }
    assert_raises(Calx::Error) { Calx.read(path, format: :xlsb) }
    assert_raises(Calx::Error) { Calx.read(path, format: :ods) }
  end
end
