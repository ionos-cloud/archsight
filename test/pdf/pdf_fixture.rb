# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "archsight/pdf"
require "archsight/pdf/cache"

# A resources directory with a page, a template, a logo and an image, for the PDF tests
module PdfFixture
  SVG = '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20"><rect width="40" height="20" fill="#336699"/></svg>'

  PAGE = <<~MD
    ---
    title: Handbook
    owner: Pat Example <pat@example.com>
    updated: 2026-05-04
    tags: pdf:cover, pdf:toc, version:2.1, pdf:template:brand
    properties:
      Classification: Confidential
    ---
    # Handbook

    ## Intro

    Some *text* with a [[Other]] link.

    ![logo](img/pic.svg)
  MD

  TEMPLATES = <<~YAML
    ---
    apiVersion: architecture/v1alpha1
    kind: Config
    metadata:
      name: Config:PDF:default
      annotations:
        config/type: pdf
        pdf/color-primary: "#112233"
        pdf/classification: Internal
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: Config
    metadata:
      name: Config:PDF:brand
      annotations:
        config/type: pdf
        pdf/color-primary: "#aa0000"
        pdf/color-accent: javascript
        pdf/logo: img/logo.svg
        pdf/footer-text: Footer "quoted"
        pdf/header-meta: id,version
        pdf/lang: de
    spec: {}
  YAML

  COMPONENT = <<~YAML
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationComponent
    metadata:
      name: Billing
      annotations:
        architecture/description: |
          Handles *invoices*.
        architecture/tags: pdf:toc
    spec: {}
  YAML

  def build_resources
    isolate_user_config
    @dir = Dir.mktmpdir("archsight-pdf-test")
    FileUtils.mkdir_p(File.join(@dir, "pages", "img"))
    File.write(File.join(@dir, "pages", "handbook.md"), PAGE)
    File.write(File.join(@dir, "pages", "img", "pic.svg"), SVG)
    FileUtils.mkdir_p(File.join(@dir, "img"))
    File.write(File.join(@dir, "img", "logo.svg"), SVG)
    File.write(File.join(@dir, "templates.yaml"), TEMPLATES)
    File.write(File.join(@dir, "billing.yaml"), COMPONENT)
    Archsight.resources_dir = @dir
    @db = Archsight::Database.new(@dir, verbose: false)
    @db.reload!
  end

  def cleanup_resources
    restore_user_config
    FileUtils.remove_entry(@dir) if @dir
  end

  # The tests must not depend on the settings of the person who runs them
  def isolate_user_config
    @saved_env = ENV.to_h.slice("ARCHSIGHT_CONFIG", "ARCHSIGHT_JIRA_ISSUE_URL")
    ENV["ARCHSIGHT_CONFIG"] = File.join(Dir.tmpdir, "no-such-archsight-#{Process.pid}.yaml")
    ENV.delete("ARCHSIGHT_JIRA_ISSUE_URL")
    Archsight::JiraSettings.reset!
  end

  def restore_user_config
    %w[ARCHSIGHT_CONFIG ARCHSIGHT_JIRA_ISSUE_URL].each { |key| ENV.delete(key) }
    ENV.update(@saved_env) if @saved_env
    Archsight::JiraSettings.reset!
  end

  def typst?
    system("typst", "--version", out: File::NULL, err: File::NULL)
  end
end
