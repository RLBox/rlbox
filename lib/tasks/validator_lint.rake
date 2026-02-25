# frozen_string_literal: true

namespace :validator do
  # ---------------------------------------------------------------------------
  # validator:lint
  # Lint all validator files for common issues.
  # ---------------------------------------------------------------------------
  desc 'Lint all validator files (stale fields, data_version isolation, N+1, view alignment)'
  task lint: :environment do
    require Rails.root.join('lib/validator_linter')

    linter = ValidatorLinter.new
    issues = linter.lint_all
    linter.report(issues)

    # Honour strict mode configured in config/validator_lint_rules.yml
    config      = File.exist?('config/validator_lint_rules.yml') ? YAML.load_file('config/validator_lint_rules.yml') : {}
    strict_mode = config.dig('strict_mode') || {}

    if strict_mode['enabled'] && strict_mode['fail_on_high_severity']
      high_issues = issues.select { |i| i.severity == 'HIGH' }
      if high_issues.any?
        puts "\nLint failed: #{high_issues.size} HIGH severity issue(s) found"
        exit 1
      end
    end

    exit(issues.empty? ? 0 : 1)
  end

  # ---------------------------------------------------------------------------
  # validator:lint_single[id]
  # Lint a single validator by substring of its filename.
  # ---------------------------------------------------------------------------
  desc 'Lint a single validator (e.g. rake validator:lint_single[v001])'
  task :lint_single, [:validator_id] => :environment do |_t, args|
    require Rails.root.join('lib/validator_linter')

    unless args[:validator_id]
      puts 'Usage: rake validator:lint_single[v001]'
      exit 1
    end

    linter = ValidatorLinter.new
    issues = linter.lint_single(args[:validator_id])

    if issues.empty?
      puts "\n[PASS] #{args[:validator_id]} passed all lint checks"
      exit 0
    else
      linter.report(issues)
      exit 1
    end
  end
end
