# frozen_string_literal: true

# Define import module namespaces
module Archsight
  module Import
    module Handlers
    end

    # Where the git-based handlers clone repositories: the handler's own `cacheRoot` setting, else `import.cache_root`
    # of the user configuration (or ARCHSIGHT_IMPORT_CACHE_ROOT), else ~/.cache/archsight/git
    # @param override [String, nil] a handler's own setting
    # @return [String] the directory as configured (a `~` stays, so generated child imports keep the portable form;
    #   expand it before use)
    def self.cache_root(override = nil)
      require "archsight/user_config"
      override || Archsight::UserConfig.setting("import", "cache_root")&.to_s ||
        File.join(Dir.home, ".cache", "archsight", "git")
    end

    # The entries of `import/dependsOn`: import names and glob patterns
    # @return [Array<String>]
    def self.declared_dependencies(import)
      import.annotations["import/dependsOn"].to_s.split(",").map(&:strip).reject(&:empty?)
    end

    # Absolute path of a file below the resources directory, nil when the path leaves it
    def self.resources_path(resources_dir, rel_path)
      root = File.expand_path(resources_dir)
      path = File.expand_path(rel_path.to_s, root)
      path.start_with?("#{root}/") ? path : nil
    end

    # Hash of the files `import/config/inputs` matches (glob patterns relative to the resources directory, comma
    # separated): their paths, sizes and modification times. nil when the import declares no inputs.
    # @return [String, nil]
    def self.inputs_hash(import, resources_dir)
      patterns = import.annotations["import/config/inputs"].to_s.split(",").map(&:strip).reject(&:empty?)
      return nil if patterns.empty?

      root = File.expand_path(resources_dir)
      files = patterns.flat_map { |pattern| Dir.glob(pattern, base: root) }.uniq.sort
      stats = files.filter_map do |file|
        stat = File.stat(File.join(root, file))
        "#{file}:#{stat.size}:#{stat.mtime.to_f}" if stat.file?
      end
      require "digest"
      Digest::SHA256.hexdigest(stats.join("\n"))[0, 16]
    end

    # Whether a `import/dependsOn` entry is a glob pattern (`Import:Repo:*`)
    def self.pattern?(entry)
      entry.match?(/[*?\[]/)
    end

    # Whether an import name matches a `import/dependsOn` entry
    def self.dependency_match?(entry, name)
      pattern?(entry) ? File.fnmatch?(entry, name, File::FNM_EXTGLOB) : entry == name
    end
  end
end

require_relative "import/registry"
require_relative "import/handler"
require_relative "import/executor"
require_relative "import/handler_loader"
