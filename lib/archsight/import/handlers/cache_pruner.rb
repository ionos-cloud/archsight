# frozen_string_literal: true

# Shared helper for import handlers that clone repositories into a local
# cache directory keyed by name (see github.rb, gitlab.rb). Removes cache
# subdirectories that no longer correspond to any repo/project returned by
# the current API listing, so a renamed, moved, or deleted repo doesn't
# leave a stale clone behind that a later importer could still resolve
# against under its old name.
#
# A listing can be incomplete (throttled or empty API pages) and clones may be
# in progress, so pruning is conservative: entries touched within MIN_AGE are
# kept, and nothing is removed when it would wipe out most of the cache.
module Archsight::Import::Handlers::CachePruner
  MIN_AGE = 3600 # seconds; younger directories may be a clone in progress
  MAX_STALE_ABSOLUTE = 10 # always allowed, whatever the cache size
  MAX_STALE_FRACTION = 0.2 # larger share of the cache is treated as a bad listing

  def prune_stale_cache_entries(target_dir, current_names)
    return unless File.directory?(target_dir)

    known = current_names.to_set
    dirs = Dir.children(target_dir).select { |entry| File.directory?(File.join(target_dir, entry)) }
    stale = dirs.reject { |entry| known.include?(entry) }
    return if stale.empty?

    limit = [MAX_STALE_ABSOLUTE, (dirs.size * MAX_STALE_FRACTION).floor].max
    if stale.size > limit
      progress.warn("Not pruning #{stale.size} of #{dirs.size} cache entries in #{target_dir}: " \
                    "the project listing looks incomplete")
      return
    end

    stale.each { |entry| prune_cache_entry(File.join(target_dir, entry), entry) }
  end

  private

  def prune_cache_entry(path, name)
    return if Time.now - File.mtime(path) < MIN_AGE

    progress.warn("Pruning stale cache entry: #{name} (repo renamed, moved, or removed)")
    FileUtils.rm_rf(path)
  rescue Errno::ENOENT
    nil
  end
end
