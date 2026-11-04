# frozen_string_literal: true

require "date"
require "time"
require_relative "fast_sheet/version"

# Reads CSV, TSV and spreadsheets (xlsx, xlsm, xlsb, xls, ods) row by row
# with a Rust core (the csv and calamine crates).
#
# Errors: TypeError for an argument of the wrong type, ArgumentError for a
# value that isn't allowed, IndexError for a sheet index past the last sheet,
# Errno::ENOENT for a missing file, and FastSheet::Error for a file that
# can't be read.
module FastSheet
  # Raised when a file can't be read: corrupt, the wrong format, or (CSV) not
  # in the encoding given.
  class Error < StandardError; end

  # The native extension looks up FastSheet::Error, so load it after Error is defined.
  # Precompiled gems ship one binary per Ruby version (fast_sheet/3.4/fast_sheet);
  # a gem compiled on install has a single fast_sheet/fast_sheet.
  begin
    require "fast_sheet/#{RUBY_VERSION[/\d+\.\d+/]}/fast_sheet"
  rescue LoadError
    require "fast_sheet/fast_sheet"
  end

  # File extensions and the format each one is read as.
  FORMATS = {
    ".csv" => :csv, ".tsv" => :tsv,
    ".xlsx" => :xlsx, ".xlsm" => :xlsm, ".xlsb" => :xlsb, ".xls" => :xls, ".ods" => :ods
  }.freeze

  class << self
    # Yields each row of a sheet as an Array.
    #
    # CSV and TSV cells are Strings. Spreadsheet cells are String, Integer,
    # Float, true/false, Date (a date with no time of day), Time (local time:
    # Excel stores no zone) or nil (empty); error cells are their text, such as
    # "#N/A", and formulas give the value Excel last saved. Row 0 is the
    # sheet's first row and row[0] its column A, even when the data starts lower.
    #
    # @param path [String, #to_path] the file (a Pathname, File or Tempfile works)
    # @param format [Symbol, nil] one of the values of {FORMATS}; by default
    #   taken from the file extension
    # @param sheet [Integer, String, nil] spreadsheets only: the sheet's index
    #   (from 0) or name; the first sheet by default
    # @param col_sep [String, nil] CSV only: the one-byte separator; "," for
    #   CSV and "\t" for TSV by default
    # @param encoding [String, Encoding, nil] CSV only: the file's encoding,
    #   such as "Big5" or "Shift_JIS"; UTF-8 by default. A UTF-8 byte order
    #   mark is skipped.
    # @yieldparam row [Array]
    # @return [nil, Enumerator] an Enumerator when no block is given
    def each_row(path, format: nil, sheet: nil, col_sep: nil, encoding: nil, &block)
      return enum_for(__method__, path, format:, sheet:, col_sep:, encoding:) unless block

      path = file_path(path)
      case (format = format_of(path, format))
      when :csv, :tsv
        raise ArgumentError, "sheet: is only for spreadsheets" if sheet

        each_csv_row(path, format, col_sep, encoding, &block)
      else
        raise ArgumentError, "col_sep: and encoding: are only for CSV files" if col_sep || encoding

        index, name = sheet_ref(sheet)
        _each_workbook_row(path, format.to_s, index, name, &block)
      end
      nil
    end

    # Every row of a sheet; takes the options of {each_row}.
    # @return [Array<Array>]
    def read(path, **)
      each_row(path, **).to_a
    end

    # The names of a spreadsheet's sheets, in order.
    # @param path [String, #to_path]
    # @param format [Symbol, nil] as in {each_row}
    # @return [Array<String>]
    def sheet_names(path, format: nil)
      path = file_path(path)
      format = format_of(path, format)
      raise ArgumentError, "a #{format.upcase} file has no sheets" if %i[csv tsv].include?(format)

      _sheet_names(path, format.to_s)
    end

    private

    def file_path(path)
      path = path.to_path if path.respond_to?(:to_path)
      raise TypeError, "path must be a String or respond to #to_path, not #{path.class}" unless path.is_a?(String)
      raise Errno::ENOENT, path unless File.file?(path)

      path
    end

    def format_of(path, format)
      return FORMATS.fetch(File.extname(path).downcase) { raise ArgumentError, unknown_format(path) } unless format
      unless FORMATS.value?(format)
        raise ArgumentError,
              "unknown format #{format.inspect} (#{FORMATS.values.join(", ")})"
      end

      format
    end

    def unknown_format(path)
      "can't tell the format of #{path.inspect} from its extension; pass format: (#{FORMATS.values.join(", ")})"
    end

    def sheet_ref(sheet)
      case sheet
      when nil then [nil, nil]
      when String then [nil, sheet]
      when Integer
        raise IndexError, "sheet index #{sheet} is negative" if sheet.negative?

        [sheet, nil]
      else raise TypeError, "sheet must be an Integer or String, not #{sheet.class}"
      end
    end

    def each_csv_row(path, format, col_sep, encoding, &)
      col_sep ||= format == :tsv ? "\t" : ","
      raise TypeError, "col_sep must be a String, not #{col_sep.class}" unless col_sep.is_a?(String)
      raise ArgumentError, "col_sep must be one byte, not #{col_sep.inspect}" unless col_sep.bytesize == 1

      # Transcoded in Ruby, then parsed as UTF-8: the whole file is read into memory.
      if encoding
        encoding = Encoding.find(encoding) # ArgumentError for an unknown name
        bom = "BOM|" if encoding.name.start_with?("UTF-")
        data = File.read(path, encoding: "#{bom}#{encoding}:UTF-8")
      end
      _each_csv_row(path, data, col_sep.ord, &)
    end
  end
end
