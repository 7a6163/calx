# frozen_string_literal: true

# Reads the same data with calx and other Ruby readers.
#   bundle exec rake compile
#   BUNDLE_GEMFILE=bench/Gemfile bundle install
#   BUNDLE_GEMFILE=bench/Gemfile bundle exec ruby --yjit bench/read.rb [rows]
require "csv"
require "creek"
require "calx"
require "fast_xlsx"
require "roo"
require "simple_xlsx_reader"
require "tmpdir"
begin
  require "fastsheet" # optional: not on RubyGems in a current version, install from GitHub
rescue LoadError
  nil
end

ROWS = Integer(ARGV[0] || 200_000)

# Best time of `runs`; the block returns how many rows it read, so a reader
# that stops early (or reads lazily) can't look fast.
def best_of(expected, runs)
  Array.new(runs) do
    GC.start
    t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    count = yield
    raise "read #{count} rows, not #{expected}" unless count == expected

    Process.clock_gettime(Process::CLOCK_MONOTONIC) - t
  end.min
end

def report(title, expected, runs, readers)
  times = readers.transform_values { |read| best_of(expected, runs, &read) }
  fastest = times.values.min
  puts "\n## #{title}"
  times.each { |name, t| puts format("  %-32s %9.1f ms  %6.1fx slower", name, t * 1000, t / fastest) }
end

def count_each(enum = nil)
  n = 0
  (enum || yield).each { n += 1 }
  n
end

Dir.mktmpdir do |dir|
  simple = ->(i) { [i, i * 3.14, "item#{i}", "north", i % 7, "2026-11-04", 42, "ok", i * 2, "x"] }
  quoted = ->(i) { [i, "Smith, John", %(say "hi"), "line1\nline2", "台北市信義區", "x" * 40, i * 1.5, "a,b,c", "", "end"] }

  { "numbers and short strings" => simple, "quotes, commas, newlines and CJK" => quoted }.each do |name, row|
    path = File.join(dir, "data.csv")
    CSV.open(path, "w") { |csv| ROWS.times { |i| csv << row.(i) } }
    raise "rows differ" unless Calx.read(path) == CSV.read(path)

    report("CSV, #{name}: #{ROWS} rows x 10, #{(File.size(path) / 1e6).round(1)} MB", ROWS, 5,
           "calx Calx.each_row" => -> { count_each(Calx.each_row(path)) },
           "calx Calx.read" => -> { Calx.read(path).size },
           "csv CSV.foreach" => -> { count_each(CSV.foreach(path)) },
           "csv CSV.read" => -> { CSV.read(path).size })
  end

  path = File.join(dir, "book.xlsx")
  wb = FastXlsx::Workbook.new
  ws = wb.add_worksheet
  ROWS.times { |i| ws << [i, "item#{i}", i * 1.5, Date.new(2026, 1, 1) + (i % 365), "north"] }
  wb.save(path)

  xlsx_readers = {
    "calx Calx.each_row" => -> { count_each(Calx.each_row(path)) },
    "creek simple_rows" => -> { count_each(Creek::Book.new(path).sheets[0].simple_rows) },
    "simple_xlsx_reader rows.each" => -> { count_each(SimpleXlsxReader.open(path).sheets[0].rows) },
    "roo each_row_streaming" => -> { count_each(Roo::Excelx.new(path).to_enum(:each_row_streaming)) }
  }
  xlsx_readers["fastsheet Sheet#rows"] = -> { Fastsheet::Sheet.new(path).rows.size } if defined?(Fastsheet)

  report("xlsx: #{ROWS} rows x 5 (integer, string, float, date, string), " \
         "#{(File.size(path) / 1e6).round(1)} MB", ROWS, 3, xlsx_readers)
end

puts "\nRuby #{RUBY_VERSION}#{" +YJIT" if defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?}, #{RUBY_PLATFORM}"
