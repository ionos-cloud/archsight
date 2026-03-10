# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "archsight/import/license_analyzer"

class LicenseAnalyzerTest < Minitest::Test
  def setup
    @repo_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@repo_dir)
  end

  # --- analyze returns expected keys ---

  def test_analyze_returns_hash_with_expected_keys
    analyzer = Archsight::Import::LicenseAnalyzer.new(@repo_dir)
    result = analyzer.analyze

    %w[license_spdx license_category].each do |key|
      assert result.key?(key), "Expected result to have key '#{key}'"
    end
  end

  # --- LICENSE file detection ---

  def test_detects_apache_2_license
    write_license("Apache License\nVersion 2.0, January 2004")
    result = analyze

    assert_equal "Apache-2.0", result["license_spdx"]
    assert_equal "LICENSE", result["license_file"]
    assert_equal "permissive", result["license_category"]
  end

  def test_detects_mit_license
    write_license("MIT License\n\nPermission is hereby granted, free of charge")
    result = analyze

    assert_equal "MIT", result["license_spdx"]
    assert_equal "permissive", result["license_category"]
  end

  def test_detects_gpl3_license
    write_license("GNU GENERAL PUBLIC LICENSE\nVersion 3, 29 June 2007")
    result = analyze

    assert_equal "GPL-3.0", result["license_spdx"]
    assert_equal "copyleft", result["license_category"]
  end

  def test_detects_gpl2_license
    write_license("GNU GENERAL PUBLIC LICENSE\nVersion 2, June 1991")
    result = analyze

    assert_equal "GPL-2.0", result["license_spdx"]
    assert_equal "copyleft", result["license_category"]
  end

  def test_detects_agpl3_license
    write_license("GNU AFFERO GENERAL PUBLIC LICENSE\nVersion 3, 19 November 2007")
    result = analyze

    assert_equal "AGPL-3.0", result["license_spdx"]
    assert_equal "copyleft", result["license_category"]
  end

  def test_detects_lgpl3_license
    write_license("GNU LESSER GENERAL PUBLIC LICENSE\nVersion 3, 29 June 2007")
    result = analyze

    assert_equal "LGPL-3.0", result["license_spdx"]
    assert_equal "weak-copyleft", result["license_category"]
  end

  def test_detects_mpl2_license
    write_license("Mozilla Public License Version 2.0")
    result = analyze

    assert_equal "MPL-2.0", result["license_spdx"]
    assert_equal "weak-copyleft", result["license_category"]
  end

  def test_detects_bsd3_license
    write_license("BSD 3-Clause License\nRedistribution and use in source...")
    result = analyze

    assert_equal "BSD-3-Clause", result["license_spdx"]
    assert_equal "permissive", result["license_category"]
  end

  def test_detects_isc_license
    write_license("ISC License\n\nCopyright (c) 2024...")
    result = analyze

    assert_equal "ISC", result["license_spdx"]
    assert_equal "permissive", result["license_category"]
  end

  def test_detects_unlicense
    write_license("This is free and unencumbered software released into the public domain.")
    result = analyze

    assert_equal "Unlicense", result["license_spdx"]
    assert_equal "permissive", result["license_category"]
  end

  def test_detects_eupl_license
    write_license("European Union Public Licence 1.2")
    result = analyze

    assert_equal "EUPL-1.2", result["license_spdx"]
    assert_equal "weak-copyleft", result["license_category"]
  end

  # --- LICENCE spelling variant ---

  def test_detects_licence_spelling_variant
    File.write(File.join(@repo_dir, "LICENCE"), "MIT License\n\nPermission is hereby granted, free of charge")
    result = analyze

    assert_equal "MIT", result["license_spdx"]
    assert_equal "LICENCE", result["license_file"]
  end

  # --- COPYING file ---

  def test_detects_copying_file
    File.write(File.join(@repo_dir, "COPYING"), "GNU GENERAL PUBLIC LICENSE\nVersion 3, 29 June 2007")
    result = analyze

    assert_equal "GPL-3.0", result["license_spdx"]
    assert_equal "COPYING", result["license_file"]
  end

  # --- LICENSE.md variant ---

  def test_detects_license_md
    File.write(File.join(@repo_dir, "LICENSE.md"), "MIT License\n\nPermission is hereby granted, free of charge")
    result = analyze

    assert_equal "MIT", result["license_spdx"]
    assert_equal "LICENSE.md", result["license_file"]
  end

  # --- SPDX header detection ---

  def test_detects_spdx_header_in_source_file
    File.write(File.join(@repo_dir, "main.go"), "// SPDX-License-Identifier: Apache-2.0\npackage main\n")
    result = analyze

    assert_equal "Apache-2.0", result["license_spdx"]
    assert_equal "permissive", result["license_category"]
  end

  def test_spdx_header_takes_priority_over_missing_license_file
    File.write(File.join(@repo_dir, "lib.rs"), "// SPDX-License-Identifier: MIT\n")
    result = analyze

    assert_equal "MIT", result["license_spdx"]
  end

  # --- Manifest detection ---

  def test_detects_license_from_package_json
    File.write(File.join(@repo_dir, "package.json"), '{"name":"test","license":"ISC"}')
    result = analyze

    assert_equal "ISC", result["license_spdx"]
    assert_equal "permissive", result["license_category"]
  end

  def test_detects_license_from_gemspec
    File.write(File.join(@repo_dir, "test.gemspec"), 'Gem::Specification.new { |s| s.license = "MIT" }')
    result = analyze

    assert_equal "MIT", result["license_spdx"]
  end

  def test_detects_license_from_cargo_toml
    File.write(File.join(@repo_dir, "Cargo.toml"), "[package]\nname = \"test\"\nlicense = \"Apache-2.0\"\n")
    result = analyze

    assert_equal "Apache-2.0", result["license_spdx"]
  end

  # --- No license ---

  def test_returns_noassertion_when_no_license_found
    result = analyze

    assert_equal "NOASSERTION", result["license_spdx"]
    assert_equal "unknown", result["license_category"]
  end

  def test_returns_noassertion_for_unrecognized_license_content
    write_license("This is a custom proprietary license with no known pattern.")
    result = analyze

    assert_equal "NOASSERTION", result["license_spdx"]
    assert_equal "LICENSE", result["license_file"]
    assert_equal "unknown", result["license_category"]
  end

  # --- Ecosystem detection ---

  def test_detects_go_ecosystem
    File.write(File.join(@repo_dir, "go.mod"), "module example.com/test\n\ngo 1.21\n")
    result = analyze

    assert_includes result["dependency_ecosystems"].to_s, "go"
  end

  def test_detects_python_ecosystem
    File.write(File.join(@repo_dir, "requirements.txt"), "flask==2.0\nrequests==2.28\n")
    result = analyze

    assert_includes result["dependency_ecosystems"].to_s, "python"
  end

  def test_detects_ruby_ecosystem
    File.write(File.join(@repo_dir, "Gemfile"), "source 'https://rubygems.org'\ngem 'rails'\n")
    result = analyze

    assert_includes result["dependency_ecosystems"].to_s, "ruby"
  end

  def test_detects_nodejs_ecosystem
    File.write(File.join(@repo_dir, "package.json"), '{"name":"test","dependencies":{"express":"4.0"}}')
    result = analyze

    assert_includes result["dependency_ecosystems"].to_s, "nodejs"
  end

  def test_detects_rust_ecosystem
    File.write(File.join(@repo_dir, "Cargo.toml"), "[package]\nname = \"test\"\nlicense = \"MIT\"\n")
    result = analyze

    assert_includes result["dependency_ecosystems"].to_s, "rust"
  end

  def test_detects_java_ecosystem
    File.write(File.join(@repo_dir, "pom.xml"), "<project><dependencies><dependency></dependency></dependencies></project>")
    result = analyze

    assert_includes result["dependency_ecosystems"].to_s, "java"
  end

  def test_no_ecosystem_detected_for_empty_repo
    result = analyze

    assert_nil result["dependency_ecosystems"]
    assert_equal 0, result["dependency_count"]
  end

  # --- Dependency fallback counting ---

  def test_counts_go_sum_entries_as_fallback
    File.write(File.join(@repo_dir, "go.mod"), "module example.com/test\n\ngo 1.21\n")
    File.write(File.join(@repo_dir, "go.sum"), <<~SUM)
      github.com/pkg/errors v0.9.1 h1:abc
      github.com/pkg/errors v0.9.1/go.mod h1:def
      golang.org/x/sys v0.10.0 h1:ghi
      golang.org/x/sys v0.10.0/go.mod h1:jkl
    SUM
    result = analyze

    assert_equal 2, result["dependency_count"]
  end

  def test_counts_requirements_txt_as_fallback
    File.write(File.join(@repo_dir, "requirements.txt"), "flask==2.0\nrequests==2.28\nnumpy>=1.24\n")
    result = analyze

    assert_equal 3, result["dependency_count"]
  end

  def test_counts_gemfile_lock_entries_as_fallback
    File.write(File.join(@repo_dir, "Gemfile"), "source 'https://rubygems.org'\n")
    File.write(File.join(@repo_dir, "Gemfile.lock"), <<~LOCK)
      GEM
        remote: https://rubygems.org/
        specs:
          rake (13.0.6)
          minitest (5.18.0)
          simplecov (0.22.0)

      PLATFORMS
        ruby
    LOCK
    result = analyze

    assert_equal 3, result["dependency_count"]
  end

  def test_counts_package_json_dependencies_as_fallback
    File.write(File.join(@repo_dir, "package.json"), <<~JSON)
      {"name":"test","dependencies":{"express":"4.0","lodash":"4.17"},"devDependencies":{"jest":"29.0"}}
    JSON
    result = analyze

    assert_equal 3, result["dependency_count"]
  end

  # --- Risk classification ---

  def test_risk_unknown_when_no_deps
    result = analyze

    assert_equal "unknown", result["dependency_risk"]
  end

  def test_risk_low_with_only_unknown_deps_counted_as_copyleft
    # When all deps are unknown, risk should be copyleft (many unknowns)
    File.write(File.join(@repo_dir, "requirements.txt"), "flask==2.0\nrequests==2.28\n")
    result = analyze

    # Fallback counting produces "unknown" licenses, which triggers copyleft risk
    assert_equal "copyleft", result["dependency_risk"]
  end

  # --- Copyleft detection ---

  def test_copyleft_unknown_when_no_deps
    result = analyze

    assert_equal "unknown", result["dependency_copyleft"]
  end

  # --- License file priority ---

  def test_license_file_has_priority_over_manifest
    write_license("Apache License\nVersion 2.0, January 2004")
    File.write(File.join(@repo_dir, "package.json"), '{"name":"test","license":"MIT"}')
    result = analyze

    # SPDX header > LICENSE file > manifest; here LICENSE file wins over package.json
    assert_equal "Apache-2.0", result["license_spdx"]
  end

  def test_spdx_header_has_priority_over_license_file
    write_license("MIT License\n\nPermission is hereby granted, free of charge")
    File.write(File.join(@repo_dir, "main.go"), "// SPDX-License-Identifier: Apache-2.0\npackage main\n")
    result = analyze

    assert_equal "Apache-2.0", result["license_spdx"]
  end

  # --- Multiple ecosystems ---

  def test_detects_multiple_ecosystems
    File.write(File.join(@repo_dir, "go.mod"), "module example.com/test\n\ngo 1.21\n")
    File.write(File.join(@repo_dir, "requirements.txt"), "flask==2.0\n")
    result = analyze

    ecosystems = result["dependency_ecosystems"].to_s.split(",")

    assert_includes ecosystems, "go"
    assert_includes ecosystems, "python"
  end

  # --- Language filtering ---

  def test_languages_option_limits_ecosystem_detection
    # Both manifest files exist, but only Go language is declared
    File.write(File.join(@repo_dir, "go.mod"), "module example.com/test\n\ngo 1.21\n")
    File.write(File.join(@repo_dir, "requirements.txt"), "flask==2.0\n")
    result = analyze(languages: %w[Go])

    ecosystems = result["dependency_ecosystems"].to_s.split(",")

    assert_includes ecosystems, "go"
    refute_includes ecosystems, "python"
  end

  def test_languages_option_maps_javascript_to_nodejs
    File.write(File.join(@repo_dir, "package.json"), '{"name":"t","dependencies":{"express":"4"}}')
    result = analyze(languages: %w[JavaScript])

    assert_includes result["dependency_ecosystems"].to_s, "nodejs"
  end

  def test_languages_option_maps_kotlin_to_java
    File.write(File.join(@repo_dir, "pom.xml"), "<project><dependencies><dependency></dependency></dependencies></project>")
    result = analyze(languages: %w[Kotlin])

    assert_includes result["dependency_ecosystems"].to_s, "java"
  end

  def test_no_languages_scans_all_ecosystems
    # Without languages option, all ecosystems with manifests are detected
    File.write(File.join(@repo_dir, "go.mod"), "module example.com/test\n\ngo 1.21\n")
    File.write(File.join(@repo_dir, "requirements.txt"), "flask==2.0\n")
    result = analyze

    ecosystems = result["dependency_ecosystems"].to_s.split(",")

    assert_includes ecosystems, "go"
    assert_includes ecosystems, "python"
  end

  def test_languages_with_no_matching_manifest_returns_no_deps
    # Language detected but no manifest file present
    result = analyze(languages: %w[Go])

    assert_equal 0, result["dependency_count"]
  end

  # --- normalize_spdx edge cases ---

  def test_normalize_strips_leading_paren
    write_license_manifest("(GPL-2.0")
    result = analyze

    assert_equal "GPL-2.0", result["license_spdx"]
    assert_equal "copyleft", result["license_category"]
  end

  def test_normalize_strips_leading_paren_lgpl
    write_license_manifest("(LGPL-2.1")
    result = analyze

    assert_equal "LGPL-2.1", result["license_spdx"]
    assert_equal "weak-copyleft", result["license_category"]
  end

  def test_normalize_long_form_apache
    write_license_manifest("Apache License, Version 2.0")
    result = analyze

    assert_equal "Apache-2.0", result["license_spdx"]
    assert_equal "permissive", result["license_category"]
  end

  def test_normalize_short_form_apache
    write_license_manifest("Apache 2.0")
    result = analyze

    assert_equal "Apache-2.0", result["license_spdx"]
    assert_equal "permissive", result["license_category"]
  end

  def test_normalize_the_mit_license
    write_license_manifest("The MIT License")
    result = analyze

    assert_equal "MIT", result["license_spdx"]
    assert_equal "permissive", result["license_category"]
  end

  def test_normalize_bsd_3_clause_with_space
    write_license_manifest("BSD 3-Clause")
    result = analyze

    assert_equal "BSD-3-Clause", result["license_spdx"]
    assert_equal "permissive", result["license_category"]
  end

  def test_normalize_gnu_gpl_v2_long_form
    write_license_manifest("GNU General Public License v2")
    result = analyze

    assert_equal "GPL-2.0", result["license_spdx"]
    assert_equal "copyleft", result["license_category"]
  end

  def test_normalize_dual_license_picks_first
    write_license_manifest("MIT/Apache-2.0")
    result = analyze

    assert_equal "MIT", result["license_spdx"]
    assert_equal "permissive", result["license_category"]
  end

  def test_normalize_dual_license_or_syntax
    write_license_manifest("MIT OR Apache-2.0")
    result = analyze

    assert_equal "MIT", result["license_spdx"]
    assert_equal "permissive", result["license_category"]
  end

  def test_normalize_unlicensed_to_proprietary
    write_license_manifest("UNLICENSED")
    result = analyze

    assert_equal "proprietary", result["license_spdx"]
    assert_equal "proprietary", result["license_category"]
  end

  def test_normalize_copyright_notice_to_proprietary
    write_license_manifest("Copyright (C) 2024 Acme Corp. Proprietary License")
    result = analyze

    assert_equal "proprietary", result["license_spdx"]
    assert_equal "proprietary", result["license_category"]
  end

  def test_normalize_c_notice_to_proprietary
    write_license_manifest("(c) 1&1 IONOS Cloud GmbH")
    result = analyze

    assert_equal "proprietary", result["license_spdx"]
    assert_equal "proprietary", result["license_category"]
  end

  def test_normalize_domain_to_proprietary
    write_license_manifest("ionos.com")
    result = analyze

    assert_equal "proprietary", result["license_spdx"]
    assert_equal "proprietary", result["license_category"]
  end

  def test_normalize_profitbricks_domain_to_proprietary
    write_license_manifest("profitbricks.com")
    result = analyze

    assert_equal "proprietary", result["license_spdx"]
    assert_equal "proprietary", result["license_category"]
  end

  def test_normalize_ionos_internal_to_proprietary
    write_license_manifest("IONOS internal")
    result = analyze

    assert_equal "proprietary", result["license_spdx"]
    assert_equal "proprietary", result["license_category"]
  end

  # --- Dependency license normalization (messy strings from tools) ---

  def test_normalize_quoted_mit
    write_license_manifest('"MIT')
    result = analyze

    assert_equal "MIT", result["license_spdx"]
  end

  def test_normalize_quoted_simplified_bsd
    write_license_manifest('"Simplified BSD')
    result = analyze

    assert_equal "BSD-2-Clause", result["license_spdx"]
  end

  def test_normalize_0bsd
    write_license_manifest("0BSD")
    result = analyze

    assert_equal "0BSD", result["license_spdx"]
    assert_equal "permissive", result["license_category"]
  end

  def test_normalize_apache_star
    write_license_manifest("Apache*")
    result = analyze

    assert_equal "Apache-2.0", result["license_spdx"]
  end

  def test_normalize_mit_star
    write_license_manifest("MIT*")
    result = analyze

    assert_equal "MIT", result["license_spdx"]
  end

  def test_normalize_custom_url_to_proprietary
    write_license_manifest("Custom: https://github.com/facebook/create-react-app")
    result = analyze

    assert_equal "proprietary", result["license_spdx"]
    assert_equal "proprietary", result["license_category"]
  end

  def test_normalize_custom_localhost_to_proprietary
    write_license_manifest("Custom: http://localhost")
    result = analyze

    assert_equal "proprietary", result["license_spdx"]
  end

  def test_normalize_gnu_lgpl_three
    write_license_manifest("GNU LGPL 3")
    result = analyze

    assert_equal "LGPL-3.0", result["license_spdx"]
    assert_equal "weak-copyleft", result["license_category"]
  end

  def test_normalize_gnu_lesser_general_public_license
    write_license_manifest("GNU Lesser General Public License")
    result = analyze

    assert_equal "LGPL-2.1", result["license_spdx"]
    assert_equal "weak-copyleft", result["license_category"]
  end

  def test_normalize_cddl_plus_gplv2
    write_license_manifest("CDDL + GPLv2 with classpath exception")
    result = analyze

    assert_equal "CDDL-1.0", result["license_spdx"]
    assert_equal "weak-copyleft", result["license_category"]
  end

  def test_normalize_new_bsd
    write_license_manifest("New BSD")
    result = analyze

    assert_equal "BSD-3-Clause", result["license_spdx"]
    assert_equal "permissive", result["license_category"]
  end

  def test_normalize_simplified_bsd
    write_license_manifest("Simplified BSD")
    result = analyze

    assert_equal "BSD-2-Clause", result["license_spdx"]
    assert_equal "permissive", result["license_category"]
  end

  def test_normalize_unknown_uppercase
    write_license_manifest("UNKNOWN")
    result = analyze

    assert_equal "unknown", result["license_spdx"]
  end

  def test_normalize_ruby_license
    write_license_manifest("ruby")
    result = analyze

    assert_equal "Ruby", result["license_spdx"]
    assert_equal "permissive", result["license_category"]
  end

  def test_normalize_parenthesized_or_expression
    write_license_manifest("(MIT OR CC0-1.0)")
    result = analyze

    assert_equal "MIT", result["license_spdx"]
  end

  # --- SPDX gem validation (known_spdx?) ---

  def test_dual_license_recognizes_spdx_id_not_in_categories
    # Artistic-2.0 is a valid SPDX ID but not in our CATEGORIES hash;
    # the gem should still recognize it during dual-license splitting
    write_license_manifest("Artistic-2.0/MIT")
    result = analyze

    assert_equal "Artistic-2.0", result["license_spdx"]
  end

  def test_dual_license_recognizes_mpl_2_0_plus_uncommon_spdx
    # Zlib is valid SPDX but was never in the old hardcoded list
    write_license_manifest("Zlib OR MIT")
    result = analyze

    assert_equal "Zlib", result["license_spdx"]
  end

  def test_dual_license_recognizes_custom_value_noassertion
    write_license_manifest("NOASSERTION/MIT")
    result = analyze

    assert_equal "NOASSERTION", result["license_spdx"]
  end

  def test_dual_license_skips_unrecognized_picks_known
    # "FooBar-1.0" is not a real SPDX ID; should skip it and pick MIT
    write_license_manifest("FooBar-1.0/MIT")
    result = analyze

    assert_equal "MIT", result["license_spdx"]
  end

  # --- BUSL-1.1 (source-available) ---

  def test_detects_busl_license_file
    write_license("Business Source License 1.1\nLicensor: Acme Corp")
    result = analyze

    assert_equal "BUSL-1.1", result["license_spdx"]
  end

  def test_busl_categorized_as_source_available
    assert_equal "source-available",
                 Archsight::Import::LicenseAnalyzer::CATEGORY_LOOKUP["BUSL-1.1"]
  end

  # --- SpdxLicenses gem integration ---

  def test_spdx_gem_recognizes_common_licenses
    %w[MIT Apache-2.0 GPL-3.0-only BSD-3-Clause ISC].each do |id|
      assert SpdxLicenses.exist?(id), "Expected SpdxLicenses to recognize #{id}"
    end
  end

  def test_spdx_gem_rejects_invalid_ids
    %w[NOASSERTION proprietary unknown FooBar-1.0].each do |id|
      refute SpdxLicenses.exist?(id), "Expected SpdxLicenses to NOT recognize #{id}"
    end
  end

  def test_custom_license_values_includes_our_special_ids
    custom = Archsight::Import::LicenseAnalyzer::CUSTOM_LICENSE_VALUES

    assert_includes custom, "NOASSERTION"
    assert_includes custom, "proprietary"
    assert_includes custom, "unknown"
  end

  # --- Lint validation (TechnologyArtifact license/spdx annotation) ---

  def test_spdx_annotation_validates_valid_license
    annotation = spdx_annotation

    assert_empty annotation.validate("MIT")
    assert_empty annotation.validate("Apache-2.0")
    assert_empty annotation.validate("GPL-3.0-only")
  end

  def test_spdx_annotation_validates_custom_values
    annotation = spdx_annotation

    assert_empty annotation.validate("NOASSERTION")
    assert_empty annotation.validate("proprietary")
    assert_empty annotation.validate("unknown")
  end

  def test_spdx_annotation_rejects_invalid_license
    annotation = spdx_annotation
    errors = annotation.validate("NotARealLicense-1.0")

    refute_empty errors
    assert_match(/invalid SPDX/, errors.first)
  end

  def test_spdx_annotation_has_validation
    assert_predicate spdx_annotation, :has_validation?, "license/spdx annotation should have validation"
  end

  private

  def spdx_annotation
    Archsight::Resources::TechnologyArtifact.annotations.find { |a| a.key == "license/spdx" }
  end

  # Write a license string via package.json manifest (simulates dependency-tool output)
  def write_license_manifest(license_string)
    File.write(File.join(@repo_dir, "package.json"),
               JSON.generate({ "name" => "test", "license" => license_string }))
  end

  def write_license(content)
    File.write(File.join(@repo_dir, "LICENSE"), content)
  end

  def analyze(options = {})
    Archsight::Import::LicenseAnalyzer.new(@repo_dir, options).analyze
  end
end
