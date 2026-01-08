# frozen_string_literal: true

target :lib do
  signature "sig"

  # Check public API files
  check "lib/archsight.rb"
  check "lib/archsight/version.rb"
  check "lib/archsight/configuration.rb"
  # Excluded: lib/archsight/database.rb (uses YAML.parse_stream not in stdlib RBS)
  # Excluded: lib/archsight/resources.rb (uses __dir__ which can be nil)
  check "lib/archsight/resources/base.rb"
  # Excluded: lib/archsight/query.rb (Query module/class name collision confuses type checker)
  check "lib/archsight/annotations/annotation.rb"
  check "lib/archsight/annotations/computed.rb"

  library "yaml"
end
