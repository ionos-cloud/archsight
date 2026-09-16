# frozen_string_literal: true

# Shared helper for import handlers that clone repositories into a local
# cache directory keyed by name (see github.rb, gitlab.rb). Removes cache
# subdirectories that no longer correspond to any repo/project returned by
# the current API listing, so a renamed, moved, or deleted repo doesn't
# leave a stale clone behind that a later importer could still resolve
# against under its old name.
module Archsight::Import::Handlers::CachePruner
  def prune_stale_cache_entries(target_dir, current_names)
    return unless File.directory?(target_dir)

    Dir.children(target_dir).each do |entry|
      next if current_names.include?(entry)

      stale_path = File.join(target_dir, entry)
      next unless File.directory?(stale_path)

      progress.warn("Pruning stale cache entry: #{entry} (repo renamed, moved, or removed)")
      FileUtils.rm_rf(stale_path)
    end
  end
end
