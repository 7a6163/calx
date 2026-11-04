# frozen_string_literal: true

require_relative "lib/calx/version"

Gem::Specification.new do |spec|
  spec.name = "calx"
  spec.version = Calx::VERSION
  spec.authors = ["Zac"]
  spec.email = ["579103+7a6163@users.noreply.github.com"]

  spec.summary = "Fast CSV and spreadsheet reader for Ruby with a Rust engine"
  spec.description = "Reads CSV, TSV, xlsx, xlsm, xlsb, xls and ods files row by row through a native " \
                     "Rust extension (the csv and calamine crates), several times faster than Ruby's CSV."
  spec.homepage = "https://github.com/7a6163/calx"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ bench/ Gemfile .gitignore test/ .github/ .rubocop.yml .cargo/ ext/calx/tests/])
    end
  end
  spec.require_paths = ["lib"]
  spec.extensions = ["ext/calx/extconf.rb"]

  spec.add_dependency "rb_sys", "~> 0.9.130"
end
