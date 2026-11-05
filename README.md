# calx

[![CI](https://github.com/7a6163/calx/actions/workflows/main.yml/badge.svg)](https://github.com/7a6163/calx/actions/workflows/main.yml)
[![codecov](https://codecov.io/gh/7a6163/calx/graph/badge.svg)](https://codecov.io/gh/7a6163/calx)

Read CSV, TSV and spreadsheets (xlsx, xlsm, xlsb, xls, ods) row by row from Ruby with a Rust engine ([csv](https://github.com/BurntSushi/rust-csv) and [calamine](https://github.com/tafia/calamine), via [magnus](https://github.com/matsadler/magnus)). The CSV reader is 4–16× faster than Ruby's `CSV`, and the xlsx reader 10–27× faster than simple_xlsx_reader, roo and creek ([benchmarks](#performance)).

It only reads. To write xlsx files, see its sibling [fast_xlsx](https://github.com/7a6163/fast_xlsx).

> **Status: 0.x.** The API may still change before 1.0.

## Installation

```bash
bundle add calx
```

Requires CRuby 3.3 or later. Installing from source needs a Rust toolchain.

## Usage

```ruby
require "calx"

# One Array per row; the format comes from the file extension.
Calx.each_row("sales.csv") { |row| p row }    # ["North", "120", "9.5"]
Calx.each_row("sales.xlsx") { |row| p row }   # ["North", 120, 9.5, #<Date 2026-07-03>]

rows = Calx.read("sales.xlsx", sheet: "July") # every row at once
Calx.sheet_names("sales.xlsx")                # ["June", "July"]
Calx.each_row("big.csv").first(10)            # an Enumerator without a block
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

- **CSV**: every cell is a String, as with Ruby's `CSV`. A UTF-8 byte order mark is skipped. Rows can have different lengths. A file that isn't valid UTF-8 raises `Calx::Error`, with a hint to pass `encoding:`.
- **Spreadsheets**: String, Integer, Float, `true`/`false`, `Date`, `Time` or `nil`.
  - Whole numbers come back as Integer (xlsx stores `42` and `42.0` the same way).
  - A date with no time of day is a `Date`; one with a time is a local `Time` (Excel stores no time zone).
  - Durations (`[h]:mm` formats) are the Float number of days Excel stores; in ods files they are ISO 8601 Strings such as `"PT10H10M10S"`.
  - Formulas give the value Excel last saved. Error cells give their text, such as `"#N/A"`.
  - Rows count from the sheet's first row and `row[0]` is always column A, even when the data starts lower: rows above it are `[]` and cells left of it `nil`. Every other row is padded with `nil` to the width of the used range.

### Errors

`TypeError` for an argument of the wrong type, `ArgumentError` for a value that isn't allowed (an unknown format, sheet name or encoding), `IndexError` for a sheet index past the last sheet, `Errno::ENOENT` for a missing file, and `Calx::Error` for a file that can't be read.

### Limits

- Read only: no styles, comments or merged-cell ranges, and no editing an existing file.
- A spreadsheet's sheet is loaded into memory whole before its rows are yielded. A CSV file is read as it goes, except with `encoding:`, which reads the whole file to transcode it.

## Performance

200,000 rows read with each library, Ruby 3.4.11 with YJIT, Apple Silicon (arm64). Best of 5 runs for CSV, 3 for xlsx; every run must read all 200,000 rows. Lower is better.

**CSV, 10 columns of numbers and short strings** (12.5 MB)

| Library | Method | Time | vs calx |
|---|---|---:|---:|
| **calx** 0.1.0 | `Calx.each_row` | **51 ms** | 1.0× |
| **calx** 0.1.0 | `Calx.read` | **49 ms** | 1.0× |
| csv 3.3.7 | `CSV.foreach` | 231 ms | 4.5× slower |
| csv 3.3.7 | `CSV.read` | 327 ms | 6.4× slower |

**CSV, 10 columns with quotes, commas, newlines and CJK** (26.2 MB)

| Library | Method | Time | vs calx |
|---|---|---:|---:|
| **calx** 0.1.0 | `Calx.each_row` | **64 ms** | 1.0× |
| **calx** 0.1.0 | `Calx.read` | **64 ms** | 1.0× |
| csv 3.3.7 | `CSV.foreach` | 865 ms | 13.4× slower |
| csv 3.3.7 | `CSV.read` | 1,012 ms | 15.7× slower |

**xlsx, 5 columns: integer, string, float, date, string** (6.0 MB, written by fast_xlsx)

| Library | Method | Time | vs calx |
|---|---|---:|---:|
| **calx** 0.1.0 | `Calx.each_row` | **222 ms** | 1.0× |
| fastsheet 0.2.0 (GitHub) | `Sheet.new(path).rows` | 281 ms | 1.3× slower |
| simple_xlsx_reader 5.1.0 | `rows.each` | 2,411 ms | 10.8× slower |
| roo 4.0.0 | `each_row_streaming` | 5,117 ms | 23.0× slower |
| creek 2.6.3 | `simple_rows` | 6,014 ms | 27.0× slower |

Ruby's `CSV` slows down most on quoted fields, which real exports and uploads usually have. The libraries don't return quite the same thing: roo yields cell objects and creek yields a Hash per row, while calx and simple_xlsx_reader yield Arrays of values.

fastsheet also uses calamine, so it is close on speed, but it builds every row before returning any and its values differ: whole numbers come back as Float (`1.0`), dates as a `Time` at midnight UTC (so `2026-01-02 08:00 +0800` in Taipei, and the previous day west of UTC), and error cells as `nil`. It reads the first sheet only and no CSV. Its current version is not on RubyGems (0.1.1 there is from 2017), so the benchmark includes it only when it is installed from [GitHub](https://github.com/dmk/fastsheet).

Most of calx's time goes into making the Ruby Strings and Arrays: parsing alone is about 5× faster again. Times move by 10–30% between runs, so treat the ratios as rough. Run it yourself:

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
cargo clippy --manifest-path ext/calx/Cargo.toml --all-targets -- -D warnings
```

All behaviour is tested from Ruby (`test/`); there are no Rust unit tests.

Coverage of the Rust extension while the Ruby tests run (needs [cargo-llvm-cov](https://github.com/taiki-e/cargo-llvm-cov) and `rustup component add llvm-tools-preview`). CI uploads it to Codecov.

```bash
rm -rf tmp lib/calx/calx.bundle         # force an instrumented rebuild
eval "$(cargo llvm-cov show-env --sh)"
bundle exec rake compile test
cargo llvm-cov report --release                     # or --lcov / --html
```

Rebuild in a clean shell afterwards (`rm -rf tmp && bundle exec rake compile`) so the everyday build is not instrumented.

Mutation tests ([cargo-mutants](https://mutants.rs)) change the Rust source one small edit at a time and check that a Ruby test fails for each change. `ext/calx/tests/ruby_suite.rs` connects the two: it rebuilds the extension and runs the Ruby suite, so `cargo test` covers the Ruby tests too. Mutants that can't change behaviour are excluded in `.cargo/mutants.toml`.

```bash
cargo install cargo-mutants
cargo mutants --file ext/calx/src/lib.rs --jobs 4   # ~1.5 minutes; results in mutants.out/
```

Mutants listed in `mutants.out/missed.txt` point at behaviour no test checks. The `Mutation tests` workflow runs this weekly and on demand. Dependabot opens weekly update PRs for the gems, crates and GitHub Actions.

The xls, xlsb, ods and some xlsx files in `test/fixtures` come from calamine's test suite (MIT).

Releasing: bump `lib/calx/version.rb`, update the CHANGELOG, and push a `vX.Y.Z` tag. The `Build gems` workflow builds the platform gems and publishes them to RubyGems.

## License

MIT
