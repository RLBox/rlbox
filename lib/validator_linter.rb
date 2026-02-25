# frozen_string_literal: true

# ValidatorLinter — static code analysis for validator files.
#
# Detects four categories of issues:
#   1. stale_field      — model field referenced in validator no longer exists / has been renamed
#   2. data_version     — query in verify method is missing data_version isolation filter
#   3. missing_includes — association accessed without eager-loading (N+1 risk)
#   4. view_alignment   — field used in validator is not found in the declared view files
#
# Rules 1, 3, and 4 are configured via config/validator_lint_rules.yml (optional).
# Rule 2 (data_version) is driven dynamically from DataVersionable.models.
#
# Usage:
#   linter = ValidatorLinter.new
#   issues = linter.lint_all
#   linter.report(issues)
#
# Zero-config: all rule sets default to empty when the config file is absent.

require 'yaml'

class ValidatorLinter
  class Issue
    attr_reader :validator, :severity, :category, :message, :suggestion, :line, :details

    def initialize(validator:, severity:, category:, message:, suggestion: nil, line: nil, details: {})
      @validator  = validator
      @severity   = severity   # HIGH, MEDIUM, LOW
      @category   = category   # stale_field | data_version | missing_includes | view_alignment
      @message    = message
      @suggestion = suggestion
      @line       = line
      @details    = details
    end

    def to_s
      output  = "[#{@severity}] #{@validator}"
      output += " (line #{@line})" if @line
      output += "\n  → #{@message}"
      output += "\n  → Suggestion: #{@suggestion}" if @suggestion
      output
    end
  end

  def initialize(config_path: Rails.root.join('config/validator_lint_rules.yml'))
    @config_path     = config_path
    @config          = load_config
    @validator_files = find_validator_files
  end

  # Lint every validator file and return all issues.
  def lint_all
    puts "🔍 Scanning #{@validator_files.size} validators..."
    issues = []
    @validator_files.each do |file|
      name    = extract_validator_name(file)
      content = File.read(file)
      issues += check_stale_fields(name, content, file)
      issues += check_data_version(name, content, file)
      issues += check_missing_includes(name, content, file)
      issues += check_view_alignment(name, content, file)
    end
    issues
  end

  # Lint a single validator identified by a substring of its filename.
  def lint_single(validator_id)
    file = @validator_files.find { |f| File.basename(f, '.rb').include?(validator_id) }
    unless file
      puts "❌ Validator not found: #{validator_id}"
      return []
    end

    name    = extract_validator_name(file)
    content = File.read(file)
    issues  = []
    issues += check_stale_fields(name, content, file)
    issues += check_data_version(name, content, file)
    issues += check_missing_includes(name, content, file)
    issues += check_view_alignment(name, content, file)
    issues
  end

  # Print a formatted report for the given issues array.
  def report(issues)
    return success_report if issues.empty?

    grouped = issues.group_by(&:severity)

    puts "\n🔍 Validator Lint Report"
    puts "=" * 60
    puts "\n❌ Found #{issues.size} issue(s):\n"

    %w[HIGH MEDIUM LOW].each do |sev|
      next unless grouped[sev]
      puts "\n#{severity_icon(sev)} #{sev} Priority (#{grouped[sev].size} issues):"
      puts "-" * 60
      grouped[sev].each_with_index { |issue, i| puts "\n#{i + 1}. #{issue}" }
    end

    puts "\n" + "=" * 60
    puts "💡 Run 'rake validator:lint_single[id]' to check a specific validator"
    puts ""
    issues
  end

  private

  # ── Check 1: stale field references ──────────────────────────────────────

  def check_stale_fields(validator_name, content, _file_path)
    issues = []
    stale_fields = @config.dig('rules', 'stale_fields') || {}

    stale_fields.each do |model, field_configs|
      field_configs.each do |field_config|
        field    = field_config['field']
        patterns = generate_field_patterns(model, field)

        patterns.each do |pattern|
          next unless content.match?(pattern)

          issues << Issue.new(
            validator:  validator_name,
            severity:   field_config['severity'] || 'HIGH',
            category:   'stale_field',
            message:    "References stale field #{model}.#{field}",
            suggestion: field_config['alternative'] || "Check which field the frontend actually uses",
            line:       find_line_number(content, pattern),
            details:    { model: model, field: field, reason: field_config['reason'] }
          )
          break
        end
      end
    end

    issues
  end

  # ── Check 2: missing data_version filter in verify ────────────────────────

  def check_data_version(validator_name, content, _file_path)
    issues = []

    verify_method = extract_method_content(content, 'verify')
    return issues unless verify_method

    # Dynamically derive business model names from the DataVersionable registry.
    # This avoids hardcoding domain-specific model lists.
    business_models = (DataVersionable.models - DataVersionable.excluded_models)
                        .select { |m| m.column_names.include?('data_version') }
                        .map(&:name)

    business_models.each do |model|
      query_patterns = [
        /#{model}\.where\([^)]*\)/,
        /#{model}\.find_by\([^)]*\)/,
        /#{model}\.order\([^)]*\)/,
        /#{model}\.all/,
        /#{model}\.first/,
        /#{model}\.last/
      ]

      query_patterns.each do |pattern|
        next unless verify_method.match?(pattern)

        pos         = verify_method.index(pattern)
        query_chain = extract_query_chain(verify_method, pos)

        unless query_chain.match?(/data_version:\s*(@data_version|['"]0['"])/)
          issues << Issue.new(
            validator:  validator_name,
            severity:   'HIGH',
            category:   'data_version',
            message:    "#{model} query in verify is missing data_version isolation",
            suggestion: "Add .where(data_version: @data_version) to scope the query to this session",
            line:       find_line_number_in_method(content, 'verify', pattern),
            details:    { model: model, query_snippet: query_chain[0..100] }
          )
          break
        end
      end
    end

    issues
  end

  # ── Check 3: missing eager-loading (N+1 risk) ─────────────────────────────

  def check_missing_includes(validator_name, content, _file_path)
    issues = []
    associations = @config.dig('rules', 'common_associations') || {}

    associations.each do |model, assoc_list|
      assoc_list.each do |assoc|
        pattern = /(\w+)\.#{assoc}\.(\w+)/
        next unless content.match?(pattern)

        includes_pattern = /#{model}\.(?:where|all|find).*\.includes\(:#{assoc}\)/m
        next if content.match?(includes_pattern)

        issues << Issue.new(
          validator:  validator_name,
          severity:   'MEDIUM',
          category:   'missing_includes',
          message:    "Accesses #{model}.#{assoc} without .includes(:#{assoc})",
          suggestion: "Add .includes(:#{assoc}) to the query to avoid N+1",
          line:       find_line_number(content, pattern)
        )
      end
    end

    issues
  end

  # ── Check 4: view alignment ───────────────────────────────────────────────

  def check_view_alignment(validator_name, content, _file_path)
    issues = []
    view_mappings = @config.dig('rules', 'view_field_mappings') || {}

    view_mappings.each do |model, mapping|
      (mapping['validator_fields'] || []).each do |field|
        pattern = /#{model}.*\.#{field}/
        next unless content.match?(pattern)

        view_files  = mapping['view_files'] || []
        in_views    = view_files.any? do |vf|
          path = Rails.root.join(vf)
          File.exist?(path) && File.read(path).match?(/#{field}/)
        end

        next if in_views

        issues << Issue.new(
          validator:  validator_name,
          severity:   'MEDIUM',
          category:   'view_alignment',
          message:    "Uses #{model}.#{field} but field not found in declared view files",
          suggestion: "Verify the frontend actually uses this field, or update the mapping",
          line:       find_line_number(content, pattern),
          details:    { checked_views: view_files }
        )
      end
    end

    issues
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  def load_config
    return default_config unless File.exist?(@config_path)

    YAML.load_file(@config_path)
  rescue => e
    puts "⚠️  Failed to load #{@config_path}: #{e.message} — using default config"
    default_config
  end

  def default_config
    { 'rules' => { 'stale_fields' => {}, 'common_associations' => {}, 'view_field_mappings' => {} } }
  end

  def find_validator_files
    Dir.glob(Rails.root.join('app/validators/**/*_validator.rb')).sort
  end

  def extract_validator_name(file_path)
    File.basename(file_path, '.rb')
  end

  def generate_field_patterns(model, field)
    [
      /#{model}.*\.#{field}/,
      /#{model.downcase}\.#{field}/,
      /@\w+\.#{field}/,
      /\w+\[:\w+\]\[:#{field}\]/
    ]
  end

  def find_line_number(content, pattern)
    content.lines.each_with_index { |line, i| return i + 1 if line.match?(pattern) }
    nil
  end

  def extract_method_content(content, method_name)
    pattern = /def\s+#{method_name}\s*\n(.*?)(?=\n\s*def\s+|\n\s*private\s*\n|\n\s*end\s*\n\s*end)/m
    match   = content.match(pattern)
    match ? match[1] : nil
  end

  def extract_query_chain(text, start_position)
    remaining = text[start_position..]
    chain_pattern = /^.*?(?=\n\s*(?:add_assertion|expect|return|#|$|def\s|end\s))/m
    match = remaining.match(chain_pattern)
    match ? match[0] : remaining[0..200]
  end

  def find_line_number_in_method(content, method_name, pattern)
    in_method      = false
    method_pattern = /def\s+#{method_name}/

    content.lines.each_with_index do |line, i|
      if line.match?(method_pattern)
        in_method = true
      elsif in_method && line.match?(/^\s*def\s+|^\s*private\s*$|^\s*end\s*$/)
        in_method = false
      elsif in_method && line.match?(pattern)
        return i + 1
      end
    end
    nil
  end

  def severity_icon(severity)
    case severity
    when 'HIGH'   then '🔴'
    when 'MEDIUM' then '🟡'
    when 'LOW'    then '🟢'
    else               '⚪'
    end
  end

  def success_report
    puts "\n✅ All validators passed lint checks"
    puts "   Scanned #{@validator_files.size} validators, no issues found\n\n"
    []
  end
end
