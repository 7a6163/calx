# fast_sheet

Read CSV, TSV and spreadsheets (xlsx, xlsm, xlsb, xls, ods) row by row from Ruby with a Rust engine ([csv](https://github.com/BurntSushi/rust-csv) and [calamine](https://github.com/tafia/calamine), via [magnus](https://github.com/matsadler/magnus)). The CSV reader is 3–9× faster than Ruby's `CSV`, and the xlsx reader about 20× faster than roo.

It only reads. To write xlsx files, see its sibling [fast_xlsx](https://github.com/7a6163/fast_xlsx).

> **Status: 0.x.** The API may still change before 1.0.

## Installation

```bash
bundle add fast_sheet
```

Requires CRuby 3.3 or later. Installing from source needs a Rust toolchain.

## Usage

```ruby
require "fast_sheet"

# One Array per row; the format comes from the file extension.
FastSheet.each_row("sales.csv") { |row| p row }    # ["North", "120", "9.5"]
FastSheet.each_row("sales.xlsx") { |row| p row }   # ["North", 120, 9.5, #<Date 2026-07-03>]

rows = FastSheet.read("sales.xlsx", sheet: "July") # every row at once
FastSheet.sheet_names("sales.xlsx")                # ["June", "July"]
FastSheet.each_row("big.csv").first(10)            # an Enumerator without a block
```

Options:

| Option | For | |
|---|---|---|
| `format:` | all | `:csv`, `:tsv`, `:xlsx`, `:xlsm`, `:xlsb`, `:xls` or `:ods`, for files whose extension doesn't tell (uploads saved as temp files) |
| `sheet:` | spreadsheets | the sheet's index (from 0) or name; the first sheet by default |
| `col_sep:` | CSV | a one-byte separator; `","` (`"\t"` for `.tsv`) by default |
| `encoding:` | CSV | the file's encoding, such as `"Big5"` or `"Shift_JIS"`; UTF-8 by default |

`path` can be a String or anything with `#to_path` (Pathname, File, Tempfile, Rails' `UploadedFile`).

### What you get back

- **CSV**: every cell is a String, as with Ruby's `CSV`. A UTF-8 byte order mark is skipped. Rows can have different lengths. A file that isn't valid UTF-8 raises `FastSheet::Error`, with a hint to pass `encoding:`.
- **Spreadsheets**: String, Integer, Float, `true`/`false`, `Date`, `Time` or `nil`.
  - Whole numbers come back as Integer (xlsx stores `42` and `42.0` the same way).
  - A date with no time of day is a `Date`; one with a time is a local `Time` (Excel stores no time zone).
  - Durations (`[h]:mm` formats) are the Float number of days Excel stores; in ods files they are ISO 8601 Strings such as `"PT10H10M10S"`.
  - Formulas give the value Excel last saved. Error cells give their text, such as `"#N/A"`.
  - Rows count from the sheet's first row and `row[0]` is always column A, even when the data starts lower: rows above it are `[]` and cells left of it `nil`. Every other row is padded with `nil` to the width of the used range.

### Errors

`TypeError` for an argument of the wrong type, `ArgumentError` for a value that isn't allowed (an unknown format, sheet name or encoding), `IndexError` for a sheet index past the last sheet, `Errno::ENOENT` for a missing file, and `FastSheet::Error` for a file that can't be read.

### Limits

- Read only: no styles, comments or merged-cell ranges, and no editing an existing file.
- A spreadsheet's sheet is loaded into memory whole before its rows are yielded. A CSV file is read as it goes, except with `encoding:`, which reads the whole file to transcode it.

## Performance

200,000 rows, Ruby 3.4 with YJIT, Apple Silicon, best of 5 runs (3 for xlsx):

| File | Ruby | fast_sheet | |
|---|---|---|---|
| CSV, 10 columns of numbers and short strings (12.5 MB) | `CSV.foreach` 329 ms | 94 ms | 3.5× |
| CSV, 10 columns with quotes, commas, newlines and CJK (26.2 MB) | `CSV.foreach` 1,176 ms | 129 ms | 9.1× |
| xlsx, 5 columns (integer, string, float, date, string) | roo `each_row_streaming` 8,593 ms | 432 ms | 19.9× |

Most of fast_sheet's time goes into making the Ruby Strings and Arrays: parsing alone is about 5× faster again. Run it yourself:

```bash
bundle exec rake compile
BUNDLE_GEMFILE=bench/Gemfile bundle install
BUNDLE_GEMFILE=bench/Gemfile bundle exec ruby --yjit bench/read.rb [rows]
```

## Development

```bash
bin/setup
bundle exec rake           # compile + test + rubocop
bundle exec rbs -r date -I sig validate
cargo clippy --manifest-path ext/fast_sheet/Cargo.toml --all-targets -- -D warnings
```

The xls, xlsb, ods and some xlsx files in `test/fixtures` come from calamine's test suite (MIT).

Releasing: bump `lib/fast_sheet/version.rb`, update the CHANGELOG, and push a `vX.Y.Z` tag. The `Build gems` workflow builds the platform gems and publishes them to RubyGems.

## License

MIT
