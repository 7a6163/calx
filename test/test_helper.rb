# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "fast_sheet"
require "fast_xlsx"
require "tmpdir"

require "minitest/autorun"

# Set by ext/fast_sheet/tests/ruby_suite.rs for mutation testing. A mutant can
# hang inside the extension (looping, or deadlocked), where Ruby can't
# interrupt it, and this process outlives cargo-mutants' own timeout. A
# separate process kills it after that many seconds unless the tests finish.
if (seconds = ENV.fetch("FAST_SHEET_TEST_TIMEOUT_SECONDS", nil))
  watchdog = Process.spawn("sleep #{Integer(seconds)}; kill -9 #{Process.pid}", pgroup: true)
  Process.detach(watchdog)
  Minitest.after_run { Process.kill(:TERM, -watchdog) } # its sleep too

  # A mutant that loops while building rows (e.g. a loop that never ends) can
  # use up the CI runner's memory before the watchdog fires, and the runner
  # is shut down. Capping memory makes it fail fast. (macOS rejects the limit.)
  Process.setrlimit(:AS, 4 * (1024**3)) if RUBY_PLATFORM.include?("linux")
end

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
