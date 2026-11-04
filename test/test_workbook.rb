# frozen_string_literal: true

require "test_helper"

class TestWorkbook < Minitest::Test
  include SheetHelpers

  def test_cell_types
    time = Time.new(2026, 11, 4, 9, 30, Rational(15_250, 1000))
    path = xlsx do |wb|
      wb.add_worksheet << ["text", 42, 1.5, true, false, Date.new(2026, 11, 4), time, nil, -7]
    end

    assert_equal [["text", 42, 1.5, true, false, Date.new(2026, 11, 4), time, nil, -7]], Calx.read(path)
    assert_kind_of Integer, Calx.read(path)[0][1]
  end

  def test_rows_start_at_a1
    path = xlsx { |wb| wb.add_worksheet.write(2, 1, "B3") }

    assert_equal [[], [], [nil, "B3"]], Calx.read(path)
  end

  def test_rows_have_the_used_width
    path = xlsx do |wb|
      ws = wb.add_worksheet
      ws << %w[a b c]
      ws << %w[d]
    end

    assert_equal [%w[a b c], ["d", nil, nil]], Calx.read(path)
  end

  def test_empty_sheet
    assert_equal [], Calx.read(xlsx(&:add_worksheet))
  end

  def test_sheets
    path = xlsx do |wb|
      wb.add_worksheet("First") << ["one"]
      wb.add_worksheet("Second") << ["two"]
    end

    assert_equal %w[First Second], Calx.sheet_names(path)
    assert_equal [["one"]], Calx.read(path)
    assert_equal [["two"]], Calx.read(path, sheet: 1)
    assert_equal [["two"]], Calx.read(path, sheet: "Second")
  end

  def test_unknown_sheets
    path = xlsx { |wb| wb.add_worksheet("Only") }

    assert_raises(IndexError) { Calx.read(path, sheet: 1) }
    assert_raises(IndexError) { Calx.read(path, sheet: -1) }
    error = assert_raises(ArgumentError) { Calx.read(path, sheet: "Nope") }
    assert_match(/sheets: Only/, error.message)
    assert_raises(TypeError) { Calx.read(path, sheet: :Only) }
  end

  def test_csv_options_are_for_csv
    path = xlsx(&:add_worksheet)

    assert_raises(ArgumentError) { Calx.read(path, col_sep: ";") }
    assert_raises(ArgumentError) { Calx.read(path, encoding: "Big5") }
  end

  # Fixtures from calamine's test suite: a date, a date and time, a duration.
  %w[date.xlsx date.xlsb date.xls date_1904.xlsx].each do |name|
    define_method("test_dates_in_#{name}") do
      rows = Calx.read(fixture(name))

      assert_equal [Date.new(2021, 1, 1), 15], rows[0]
      assert_equal [Date.new(2021, 1, 2), 16], rows[1]
      assert_in_delta 10.632060185, rows[2][0], 1e-9 # duration: days
    end
  end

  def test_ods
    rows = Calx.read(fixture("date.ods"))

    assert_equal [Date.new(2021, 1, 1), 15], rows[0]
    assert_equal [Time.new(2021, 1, 1, 10, 10, 10), 16], rows[1]
    assert_equal ["PT10H10M10S", 17], rows[2]
  end

  def test_hidden_sheets_are_listed
    assert_equal %w[Visible Hidden VeryHidden Chart], Calx.sheet_names(fixture("any_sheets.xlsx"))
  end
end

class TestWorkbookNumbers < Minitest::Test
  include SheetHelpers

  # Past 2**53 a Float can't hold every integer, so such numbers stay Floats.
  def test_whole_numbers_up_to_2_pow_53_are_integers
    path = xlsx { |wb| wb.add_worksheet << [(2**53) - 1, 2.0**53, -((2**53) - 1)] }
    row = Calx.read(path)[0]

    assert_equal [(2**53) - 1, 2.0**53, -((2**53) - 1)], row
    assert_equal [Integer, Float, Integer], row.map(&:class)
  end
end
