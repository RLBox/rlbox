# frozen_string_literal: true

# DataPackLoader
#
# Loads baseline data pack files from a directory, respecting an optional
# `# depends_on: a, b` declaration at the top of each file.
#
# Design goals:
#   - Zero migration cost: existing data pack files without `depends_on:` keep
#     working under their old alphabetic ordering.
#   - Opt-in topological sort: any file that adds `# depends_on: base` at the
#     top is guaranteed to load after its dependencies, regardless of alphabetic
#     position.
#   - Cycle detection: if a cycle is detected, loading aborts with a clear
#     error pointing at the offending files.
#
# File header syntax (loose but explicit):
#
#   # frozen_string_literal: true
#   # depends_on: base, demo_user
#   #
#   # (rest of the pack)
#
# Multiple names are comma-separated. Names refer to the **basename** of other
# pack files **without** the `.rb` extension (e.g. `base` for `base.rb`). The
# `depends_on:` line must appear within the first 10 non-empty comment lines of
# the file; after that it is ignored (so docstrings later in the file cannot
# accidentally re-trigger the parser).
#
# Not a DSL: the data pack files remain plain Ruby scripts loaded via `load`.
# This keeps the pattern trivially debuggable and preserves backward
# compatibility with every fork.
class DataPackLoader
  Error = Class.new(StandardError)
  CycleError = Class.new(Error)
  MissingDependencyError = Class.new(Error)

  DEPENDS_ON_REGEX = /^\s*#\s*depends_on:\s*(.+?)\s*$/i.freeze
  HEADER_SCAN_LINES = 40 # scan up to N lines for the depends_on header

  attr_reader :dir

  def initialize(dir)
    @dir = Pathname.new(dir)
  end

  # Returns files in topological load order.
  # Accepts an optional :only filter (basenames or full paths) for testing.
  def load_order
    files = Dir.glob(@dir.join('*.rb')).sort
    return [] if files.empty?

    # Build basename → path map for dependency lookup
    by_name = files.each_with_object({}) do |path, hash|
      hash[File.basename(path, '.rb')] = path
    end

    # Parse deps for each file
    deps = files.each_with_object({}) do |path, hash|
      hash[path] = parse_depends_on(path)
    end

    # Validate all named dependencies exist
    deps.each do |path, names|
      names.each do |name|
        unless by_name.key?(name)
          raise MissingDependencyError,
                "#{File.basename(path)} declares `depends_on: #{name}` but no data pack " \
                "named '#{name}.rb' exists in #{@dir}"
        end
      end
    end

    # Legacy rule kept for backward compat: if `base.rb` exists and no file
    # explicitly depends_on it, still load it first. Fork projects commonly
    # assume `base.rb` runs before everything without declaring it.
    base_path = by_name['base']
    if base_path && deps.values.none? { |names| names.include?('base') }
      deps.each do |path, names|
        next if path == base_path
        names << 'base' unless names.include?('base')
      end
    end

    topological_sort(files, by_name, deps)
  end

  private

  def parse_depends_on(path)
    return [] unless File.readable?(path)

    File.foreach(path).with_index do |line, idx|
      break if idx >= HEADER_SCAN_LINES
      # Stop scanning once we exit the comment/blank header zone — data pack
      # files are scripts so the first non-comment, non-blank line is real code.
      stripped = line.strip
      break if !stripped.empty? && !stripped.start_with?('#')

      if (m = line.match(DEPENDS_ON_REGEX))
        return m[1].split(',').map(&:strip).reject(&:empty?)
      end
    end
    []
  end

  # Deterministic topological sort (Kahn's algorithm with alphabetic tiebreak).
  def topological_sort(files, by_name, deps)
    # in_degree[path] = number of unresolved deps
    in_degree = deps.transform_values { |names| names.size }

    # For each file, which other files depend on it (reverse edges)
    dependents = Hash.new { |h, k| h[k] = [] }
    deps.each do |path, names|
      names.each do |name|
        dep_path = by_name[name]
        dependents[dep_path] << path
      end
    end

    # Start with files that have no deps, in alphabetic order for stability
    queue = in_degree.select { |_, d| d.zero? }.keys.sort
    ordered = []

    until queue.empty?
      current = queue.shift
      ordered << current
      dependents[current].sort.each do |dep_of|
        in_degree[dep_of] -= 1
        queue << dep_of if in_degree[dep_of].zero?
      end
      queue.sort! # keep alphabetic among peers
    end

    if ordered.size != files.size
      unresolved = files - ordered
      raise CycleError,
            "Cycle detected in data pack depends_on graph. Unresolved files: " \
            "#{unresolved.map { |p| File.basename(p) }.join(', ')}"
    end

    ordered
  end
end
