# frozen_string_literal: true

namespace :validator do
  # ---------------------------------------------------------------------------
  # Helper: load all app models so DataVersionable registry is fully populated
  # ---------------------------------------------------------------------------
  def load_all_models
    Dir[Rails.root.join('app/models/**/*.rb')].each { |f| require f }
  end

  # ---------------------------------------------------------------------------
  # validator:status
  # Show current validator sessions and non-baseline record counts.
  # ---------------------------------------------------------------------------
  desc 'Show active validator sessions and data summary'
  task status: :environment do
    load_all_models

    puts "\n=== Validator Status ===\n\n"

    # Active sessions
    active = ValidatorExecution.active.order(created_at: :desc)
    if active.empty?
      puts '  No active validator sessions.'
    else
      puts "  Active sessions (#{active.count}):"
      active.each do |ex|
        dv = ex.data_version || '(none)'
        puts "    • #{ex.execution_id}  user=#{ex.user_id}  data_version=#{dv}  created=#{ex.created_at.strftime('%H:%M:%S')}"
      end
    end

    puts ''

    # Non-baseline record counts per versionable model
    versionable = DataVersionable.models - DataVersionable.excluded_models
    if versionable.empty?
      puts '  No versionable models registered.'
    else
      puts '  Test data (data_version != 0):'
      total = 0
      versionable.each do |model|
        next unless model.column_names.include?('data_version')
        count = model.unscoped.where.not(data_version: '0').count
        next if count == 0
        puts "    #{model.name.ljust(30)} #{count} record(s)"
        total += count
      end
      puts "    #{'TOTAL'.ljust(30)} #{total} record(s)" if total > 0
      puts '    (none)' if total == 0
    end

    puts ''
  end

  # ---------------------------------------------------------------------------
  # validator:cleanup
  # Remove expired ValidatorExecution records and their associated test data.
  # ---------------------------------------------------------------------------
  desc 'Remove expired validator sessions (>1 hour old) and their test data'
  task cleanup: :environment do
    load_all_models

    puts "\n=== Validator Cleanup ===\n\n"

    expired = ValidatorExecution.where('created_at < ?', 1.hour.ago)
    if expired.empty?
      puts '  No expired sessions found.'
      next
    end

    expired_versions = expired.filter_map(&:data_version).uniq
    puts "  Found #{expired.count} expired session(s), data_versions: #{expired_versions.inspect}"

    # Delete test data for expired sessions from all versionable models
    versionable = DataVersionable.models - DataVersionable.excluded_models
    deleted_total = 0

    versionable.each do |model|
      next unless model.column_names.include?('data_version')
      next if expired_versions.empty?

      count = model.unscoped.where(data_version: expired_versions).delete_all
      puts "  #{model.name}: deleted #{count}" if count > 0
      deleted_total += count
    end

    # Remove the execution records themselves
    expired.delete_all
    puts "\n  Done. #{deleted_total} test record(s) removed, #{expired.count} session(s) cleared."
    puts ''
  end

  # ---------------------------------------------------------------------------
  # validator:reset_baseline
  # Wipe all test data (data_version != '0'), reload data packs.
  # Baseline data (data_version='0') is preserved unless --full is passed.
  # ---------------------------------------------------------------------------
  desc 'Clear test data and reload baseline data packs'
  task reset_baseline: :environment do
    load_all_models

    full_reset = ENV['FULL'].present?

    puts "\n=== Validator Reset Baseline#{' (FULL)' if full_reset} ===\n\n"

    versionable = DataVersionable.models - DataVersionable.excluded_models

    # Step 1: Delete test data
    if full_reset
      puts '  Step 1: Clearing ALL data (including baseline)...'
      condition = nil   # delete everything
    else
      puts "  Step 1: Clearing test data (data_version != '0')..."
      condition = { data_version: nil }   # placeholder — see below
    end

    deleted_total = 0
    versionable.each do |model|
      next unless model.column_names.include?('data_version')

      count = if full_reset
                model.unscoped.delete_all
              else
                model.unscoped.where.not(data_version: '0').delete_all
              end

      puts "  #{model.name}: deleted #{count}" if count > 0
      deleted_total += count
    end

    # Also clean up ValidatorExecution records
    exec_count = ValidatorExecution.delete_all
    puts "  ValidatorExecution: deleted #{exec_count}" if exec_count > 0

    puts "  → #{deleted_total} test record(s) removed\n\n"

    # Step 2: Reload data packs
    data_packs_dir = Rails.root.join('app/validators/support/data_packs')
    pack_files = Dir.glob(data_packs_dir.join('**/*.rb')).sort

    if pack_files.empty?
      puts '  Step 2: No data packs found — skipping baseline reload.'
      puts "          Add .rb files to app/validators/support/data_packs/ to define baseline data.\n\n"
      next
    end

    puts "  Step 2: Loading #{pack_files.size} data pack(s)..."

    # Set PostgreSQL session variable so DataVersionable writes data_version='0'
    ActiveRecord::Base.connection.execute("SET SESSION app.data_version = '0'")

    # Load base.rb first, then alphabetical.
    # Search within results so the file can live at any depth under data_packs/.
    base_file = pack_files.find { |f| File.basename(f) == 'base.rb' }
    if base_file
      pack_files.delete(base_file)
      pack_files.unshift(base_file)
    end

    pack_files.each do |file|
      filename = Pathname.new(file).relative_path_from(Rails.root).to_s
      begin
        load file
        puts "  ✓ #{filename}"
      rescue StandardError => e
        puts "  ✗ #{filename}: #{e.message}"
        puts "    #{e.backtrace.first(3).join("\n    ")}"
      end
    end

    puts "\n  Baseline reset complete.\n\n"
  end

  # ---------------------------------------------------------------------------
  # validator:validate_packs
  # Check data pack integrity: required columns, data_version='0', model inference.
  # ---------------------------------------------------------------------------
  desc 'Validate data pack integrity (null checks, data_version, model inference)'
  task validate_packs: :environment do
    load_all_models
    require Rails.root.join('lib/data_pack_validator')

    validator = DataPackValidator.new
    results   = validator.validate_all

    puts "\n=== Data Pack Validation ===\n"
    puts "  Schema version : #{results[:schema_version]}"
    puts "  Packs checked  : #{results[:pack_count]}"
    puts "  Passed         : #{results[:passed_count]}"
    puts "  Failed         : #{results[:failed_count]}"
    puts ''

    results[:packs].each do |pack_name, result|
      icon = result[:passed] ? '✓' : '✗'
      puts "  #{icon} #{pack_name}"
      result[:models].each do |m|
        status = m[:errors].empty? ? 'ok' : "#{m[:errors].size} error(s)"
        puts "      #{m[:name].ljust(30)} #{m[:count]} baseline record(s)  [#{status}]"
        m[:errors].each { |e| puts "        ✗ #{e}" }
      end
      result[:errors].each { |e| puts "    ✗ #{e}" } if result[:models].empty?
      puts ''
    end

    unless results[:all_passed]
      puts "  Data pack validation FAILED\n\n"
      exit 1
    end

    puts "  All data packs passed.\n\n"
  end

  # ---------------------------------------------------------------------------
  # validator:list
  # List all validator classes discovered under app/validators/.
  # ---------------------------------------------------------------------------
  desc 'List all available validator classes'
  task list: :environment do
    validator_files = Dir[Rails.root.join('app/validators/**/*_validator.rb')].sort

    if validator_files.empty?
      puts "\n  No validator files found under app/validators/\n\n"
      next
    end

    puts "\n=== Available Validators (#{validator_files.size}) ===\n\n"
    validator_files.each do |file|
      rel = Pathname.new(file).relative_path_from(Rails.root).to_s
      puts "  #{rel}"
    end
    puts ''
  end
end
