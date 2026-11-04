# frozen_string_literal: true

require "test_helper"

class TestCsv < Minitest::Test
  include SheetHelpers

  def test_reads_rows_as_strings
    path = temp_file("a.csv", "id,name\n1,Ann\n2,Bob\n")

    assert_equal [%w[id name], %w[1 Ann], %w[2 Bob]], FastSheet.read(path)
  end

  def test_quotes_commas_newlines_and_utf8
    path = temp_file("a.csv", %(1,"Smith, John","say ""hi""","line1\nline2",台北市\n))

    assert_equal [["1", "Smith, John", %(say "hi"), "line1\nline2", "台北市"]], FastSheet.read(path)
    assert_equal Encoding::UTF_8, FastSheet.read(path)[0][4].encoding
  end

  def test_rows_of_different_lengths
    path = temp_file("a.csv", "a,b,c\nd\ne,f\n")

    assert_equal [%w[a b c], %w[d], %w[e f]], FastSheet.read(path)
  end

  def test_empty_fields_are_empty_strings
    assert_equal [["", "x", ""]], FastSheet.read(temp_file("a.csv", ",x,\n"))
  end

  def test_skips_a_utf8_bom
    path = temp_file("a.csv", "\xEF\xBB\xBFid,name\n1,Ann\n".b)

    assert_equal %w[id name], FastSheet.read(path)[0]
  end

  def test_encoding
    path = temp_file("a.csv", "編號,名稱\n1,台北\n".encode("Big5"))

    assert_equal [%w[編號 名稱], %w[1 台北]], FastSheet.read(path, encoding: "Big5")
    assert_equal [%w[編號 名稱], %w[1 台北]], FastSheet.read(path, encoding: Encoding::Big5)
  end

  def test_invalid_utf8_suggests_an_encoding
    path = temp_file("a.csv", "編號\n".encode("Big5"))

    error = assert_raises(FastSheet::Error) { FastSheet.read(path) }
    assert_match(/encoding: "Big5"/, error.message)
  end

  def test_tsv_and_col_sep
    assert_equal [%w[a b], %w[1 2]], FastSheet.read(temp_file("a.tsv", "a\tb\n1\t2\n"))
    assert_equal [%w[a b]], FastSheet.read(temp_file("a.csv", "a;b\n"), col_sep: ";")
  end

  def test_col_sep_must_be_one_byte
    path = temp_file("a.csv", "a\n")

    assert_raises(ArgumentError) { FastSheet.read(path, col_sep: "::") }
    assert_raises(ArgumentError) { FastSheet.read(path, col_sep: "、") }
    assert_raises(TypeError) { FastSheet.read(path, col_sep: 59) }
  end

  def test_each_row_yields_and_returns_nil
    path = temp_file("a.csv", "a\nb\n")
    rows = []

    assert_nil(FastSheet.each_row(path) { |row| rows << row })
    assert_equal [%w[a], %w[b]], rows
  end

  def test_each_row_without_a_block_is_an_enumerator
    enum = FastSheet.each_row(temp_file("a.csv", "a\nb\nc\n"))

    assert_kind_of Enumerator, enum
    assert_equal [%w[a], %w[b]], enum.first(2)
  end

  def test_break_and_exceptions_leave_the_block
    path = temp_file("a.csv", "a\nb\nc\n")

    assert_equal "a", FastSheet.each_row(path) { |row| break row[0] } # rubocop:disable Lint/UnreachableLoop
    assert_raises(ZeroDivisionError) { FastSheet.each_row(path) { 1 / 0 } }
  end

  def test_sheet_options_are_for_spreadsheets
    path = temp_file("a.csv", "a\n")

    assert_raises(ArgumentError) { FastSheet.read(path, sheet: 0) }
    assert_raises(ArgumentError) { FastSheet.sheet_names(path) }
  end
end

class TestCsvEncodingName < Minitest::Test
  include SheetHelpers

  def test_utf8_encoding_skips_the_bom
    path = temp_file("a.csv", "\xEF\xBB\xBFa\n".b)

    assert_equal [%w[a]], FastSheet.read(path, encoding: "UTF-8")
  end

  def test_unknown_encoding
    assert_raises(ArgumentError) { FastSheet.read(temp_file("a.csv", "a\n"), encoding: "Klingon") }
  end
end
