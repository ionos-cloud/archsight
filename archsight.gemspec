# frozen_string_literal: true

require_relative "lib/archsight/version"

Gem::Specification.new do |spec|
  spec.name = "archsight"
  spec.version = Archsight::VERSION
  spec.authors = ["Vincent Landgraf"]
  spec.email = ["vincent.landgraf@ionos.com"]

  spec.summary = "Enterprise architecture visualization and modeling tool"
  spec.description = "Bringing enterprise architecture into focus. A Ruby gem for modeling, querying, and visualizing enterprise architecture using ArchiMate-inspired YAML resources with GraphViz visualization."
  spec.homepage = "https://github.com/ionos-cloud/archsight"
  spec.license = "Apache-2.0"
  # Read minimum Ruby version from .ruby-version (major.minor only)
  ruby_version = File.read(File.join(__dir__, ".ruby-version")).strip.split(".")[0, 2].join(".")
  spec.required_ruby_version = ">= #{ruby_version}"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/releases"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Include all files tracked by git, excluding development-only files
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ sig/ examples/ .github/ .]) ||
        f.match?(/\A(Gemfile|Steepfile|Rakefile)/)
    end
  end

  spec.bindir = "exe"
  spec.executables = ["archsight"]
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "dry-inflector", "~> 1.0"
  spec.add_dependency "fast-mcp", "~> 1.0"
  spec.add_dependency "haml", "~> 6.0"
  spec.add_dependency "kramdown", "~> 2.0"
  spec.add_dependency "kramdown-parser-gfm", "~> 1.0"
  spec.add_dependency "puma", "~> 6.0"
  spec.add_dependency "rackup", "~> 2.0"
  spec.add_dependency "rexml", "~> 3.0"
  spec.add_dependency "rouge", "~> 4.7.0"
  spec.add_dependency "sinatra", "~> 4.0"
  spec.add_dependency "sinatra-contrib", "~> 4.0"
  spec.add_dependency "thor", "~> 1.0"
end
