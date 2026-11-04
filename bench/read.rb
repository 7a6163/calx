# frozen_string_literal: true

# Rows per second reading the same data with Ruby's CSV, roo and fast_sheet.
#   bundle exec rake compile
#   BUNDLE_GEMFILE=bench/Gemfile bundle exec ruby --yjit bench/read.rb [rows]
require "csv"
require "fast_sheet"
require "fast_xlsx"
require "roo"
require "tmpdir"

ROWS = Integer(ARGV[0] || 200_000)

def best_of(runs = 5)
  Array.new(runs) do
    GC.start
    t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - t
  end.min
end

def report(title, results)
  base = results.values.first
  puts "\n## #{title}"
  results.each { |name, t| puts format("  %-24s %8.1f ms  %5.1fx", name, t * 1000, base / t) }
end

Dir.mktmpdir do |dir|
  simple = ->(i) { [i, i * 3.14, "item#{i}", "north", i % 7, "2026-11-04", 42, "ok", i * 2, "x"] }
  quoted = ->(i) { [i, "Smith, John", %(say "hi"), "line1\nline2", "台北市信義區", "x" * 40, i * 1.5, "a,b,c", "", "end"] }

  { "simple" => simple, "quoted" => quoted }.each do |name, row|
    path = File.join(dir, "#{name}.csv")
    CSV.open(path, "w") { |csv| ROWS.times { |i| csv << row.(i) } }
    raise "rows differ" unless FastSheet.read(path) == CSV.read(path)

    report("CSV, #{name}: #{ROWS} rows x 10, #{(File.size(path) / 1e6).round(1)} MB",
           "Ruby CSV.foreach" => best_of { CSV.foreach(path) { |_| } },
           "FastSheet.each_row" => best_of { FastSheet.each_row(path) { |_| } })
  end

  path = File.join(dir, "book.xlsx")
  wb = FastXlsx::Workbook.new
  ws = wb.add_worksheet
  ROWS.times { |i| ws << [i, "item#{i}", i * 1.5, Date.new(2026, 1, 1) + (i % 365), "north"] }
  wb.save(path)

  report("xlsx: #{ROWS} rows x 5 (integer, string, float, date, string)",
         "roo each_row_streaming" => best_of(3) { Roo::Excelx.new(path).each_row_streaming { |_| } },
         "FastSheet.each_row" => best_of(3) { FastSheet.each_row(path) { |_| } })
end
