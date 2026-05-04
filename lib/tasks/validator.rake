# frozen_string_literal: true

namespace :validator do
  # ---------------------------------------------------------------------------
  # validator:sync_schema_version
  # Auto-sync VALIDATED_SCHEMA_VERSION in lib/data_pack_validator.rb to match
  # the current db/schema.rb version. Call this after every db:migrate.
  # ---------------------------------------------------------------------------
  desc 'Sync data_pack_validator.rb VALIDATED_SCHEMA_VERSION with db/schema.rb'
  task sync_schema_version: :environment do
    validator_file = Rails.root.join('lib/data_pack_validator.rb')
    schema_file    = Rails.root.join('db/schema.rb')

    unless validator_file.exist?
      puts '⚠️  lib/data_pack_validator.rb not found — skipping schema version sync.'
      next
    end

    unless schema_file.exist?
      puts '⚠️  db/schema.rb not found — skipping schema version sync.'
      next
    end

    # Extract current schema version from db/schema.rb
    schema_content  = File.read(schema_file)
    schema_match    = schema_content.match(/ActiveRecord::Schema\[\d+\.\d+\]\.define\(version:\s*([\d_]+)\)/)
    unless schema_match
      puts '⚠️  Could not parse schema version from db/schema.rb — skipping.'
      next
    end
    current_version = schema_match[1]

    # Extract the version currently declared in data_pack_validator.rb
    validator_content = File.read(validator_file)
    old_match         = validator_content.match(/VALIDATED_SCHEMA_VERSION\s*=\s*'([\d_]+)'/)
    unless old_match
      puts '⚠️  VALIDATED_SCHEMA_VERSION constant not found in data_pack_validator.rb — skipping.'
      next
    end
    old_version = old_match[1]

    if current_version == old_version
      puts "✅ Schema version already in sync: #{current_version}"
      next
    end

    # Write updated version back
    new_content = validator_content.gsub(
      /VALIDATED_SCHEMA_VERSION\s*=\s*'[\d_]+'/,
      "VALIDATED_SCHEMA_VERSION = '#{current_version}'"
    )
    File.write(validator_file, new_content)

    puts '✅ data_pack_validator.rb schema version updated'
    puts "   #{old_version}  →  #{current_version}"
  end

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

    puts "  → #{deleted_total} test record(s) removed\n\n"

    # Note: ValidatorExecution 是系统表，不参与 data_version 隔离，
    # 执行记录作为审计日志永久保留，不在 reset_baseline 时清理。

    # Step 2: Reload data packs
    # 规则：所有 v1 版本数据包必须放在 data_packs/v1/ 下（非递归）。
    # 根目录下的 .rb 不是 data pack（可能是 ARCHITECTURE/README 之类的文档，
    # 或者误放的旧文件）。扫描与 BaseValidator#ensure_baseline_data_loaded 对齐。
    data_packs_dir = Rails.root.join('app/validators/support/data_packs/v1')
    pack_files = Dir.glob(data_packs_dir.join('*.rb')).sort

    if pack_files.empty?
      puts '  Step 2: No data packs found — skipping baseline reload.'
      puts "          Add .rb files to app/validators/support/data_packs/v1/ to define baseline data.\n\n"
      next
    end

    puts "  Step 2: Loading #{pack_files.size} data pack(s)..."

    # Topological sort by `# depends_on:` header (with alphabetic tiebreak).
    # Files without the header fall through to the legacy rule: `base.rb` first,
    # then alphabetical.
    require Rails.root.join('lib/data_pack_loader')
    begin
      pack_files = DataPackLoader.new(data_packs_dir).load_order
    rescue DataPackLoader::Error => e
      puts "  ✗ Data pack load order error: #{e.message}"
      exit 1
    end

    # 把 baseline 加载整个包在 allow_baseline_mutation 作用域里：
    #   - SET SESSION app.baseline_loading = 'on' → 绕过 4-op RLS policy 的 INSERT/UPDATE/DELETE 写保护
    #   - Thread.current[:allow_baseline_mutation] = true → 未来可供 Ruby 层回调兜底
    # 作用域结束自动关闭两个开关（即使 yield 抛异常也关）。
    DataVersionable.allow_baseline_mutation do
      # data pack 应该写入 data_version='0'
      ActiveRecord::Base.connection.execute("SET SESSION app.data_version = '0'")

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

  # ---------------------------------------------------------------------------
  # validator:clear_executions
  # 清空所有 ValidatorExecution 执行记录（不影响 baseline 数据）
  # 用途：当执行记录过多时手动清理，或统计需要重新开始时使用
  # ---------------------------------------------------------------------------
  desc 'Clear all ValidatorExecution records (keeps baseline data intact)'
  task clear_executions: :environment do
    puts "\n=== Clear Validator Executions ===\n\n"

    count = ValidatorExecution.count
    if count.zero?
      puts "  No execution records to clear.\n\n"
      next
    end

    puts "  Found #{count} execution record(s)."
    print "  ⚠️  This will permanently delete all test history. Continue? (yes/no): "
    
    confirmation = ENV['CONFIRM'] || $stdin.gets.chomp
    unless confirmation.downcase == 'yes'
      puts "  Cancelled.\n\n"
      next
    end

    ValidatorExecution.delete_all
    puts "  ✓ Cleared #{count} execution record(s).\n\n"
  end

  # ---------------------------------------------------------------------------
  # validator:dump_status
  # Export latest ValidatorExecution status per validator_id to JSON file.
  # Usage: rake validator:dump_status
  # ---------------------------------------------------------------------------
  desc 'Dump validator execution statuses from DB to db/validator_statuses.json'
  task dump_status: :environment do
    json_file = Rails.root.join('db/validator_statuses.json')
    statuses = {}

    ValidatorExecution.unscoped
      .where.not(validator_id: nil)
      .order(:validator_id, created_at: :desc)
      .group_by(&:validator_id)
      .each do |vid, execs|
        latest = execs.first
        statuses[vid] = {
          status: latest.status,
          score: latest.score&.to_f,
          updated_at: latest.updated_at.iso8601
        }
      end

    File.write(json_file, JSON.pretty_generate(statuses) + "\n")
    puts "✅ Dumped #{statuses.size} validator status(es) to db/validator_statuses.json"
  end

  # ---------------------------------------------------------------------------
  # validator:load_status
  # Restore validator execution statuses from JSON file into DB.
  # Skips validators that already have an execution record in DB.
  # Usage: rake validator:load_status
  # ---------------------------------------------------------------------------
  desc 'Load validator execution statuses from db/validator_statuses.json into DB'
  task load_status: :environment do
    json_file = Rails.root.join('db/validator_statuses.json')

    unless json_file.exist?
      puts '⚠️  db/validator_statuses.json not found — nothing to load.'
      next
    end

    statuses = JSON.parse(File.read(json_file))
    existing = ValidatorExecution.unscoped
      .where.not(validator_id: nil)
      .pluck(:validator_id)
      .uniq

    loaded  = 0
    skipped = 0

    statuses.each do |vid, data|
      if existing.include?(vid)
        skipped += 1
        next
      end

      next if data['status'].blank? || data['status'] == 'pending'

      ValidatorExecution.create!(
        execution_id: "restored-#{vid}-#{SecureRandom.hex(4)}",
        validator_id: vid,
        status: data['status'],
        score: data['score'],
        state: { restored_from: 'validator_statuses.json' },
        is_active: false
      )
      loaded += 1
    end

    puts "✅ Loaded #{loaded} validator status(es) from JSON (#{skipped} already existed, skipped)"
  end

  # ---------------------------------------------------------------------------
  # validator:lint_schema
  # 三者一致性校验：
  #   A) 通过 include DataVersionable 注册的 Ruby 模型
  #   B) 实际有 data_version 列的 DB 表
  #   C) 启用 RLS 且有 4 条 policy（select/insert/update/delete）的 DB 表
  #
  # 不一致的典型后果：
  #   A⊄B：模型 include 了 concern，但表没列 → boot 时会炸
  #   B⊄A：表有列但模型没 include → default_scope 失效，SELECT 会跨 session 泄数据
  #   B⊄C：表有列但 RLS 没装，policy 数量 ≠ 4 → 写保护失效，baseline 裸奔
  #
  # 注意：rlbox 底座本身默认 **不** 启用 RLS（各派生项目自己加 RLS migration）。
  # 如果当前项目没有任何 RLS policy，RLS 检查会转成 WARNING（不阻塞 CI），
  # 一旦项目加了任意一条 policy（表明它走 RLS 路线），缺少的 policy 会升级为 ERROR。
  # ---------------------------------------------------------------------------
  desc 'Lint DataVersionable models ↔ data_version columns ↔ RLS policies'
  task lint_schema: :environment do
    load_all_models

    puts "\n=== Schema Lint ===\n\n"

    conn = ActiveRecord::Base.connection

    # A) 通过 concern 注册的模型（排除 data_version_excluded! 的系统模型）
    registered_models = DataVersionable.models - DataVersionable.excluded_models
    registered_tables = registered_models.map(&:table_name).sort

    # B) 实际有 data_version 列的业务表
    db_tables_with_column = conn.tables.select do |t|
      conn.column_exists?(t, :data_version)
    end.sort

    # C) 启用 RLS 且有 4 条 policy 的表
    policy_rows = conn.execute(<<~SQL).to_a
      SELECT tablename, COUNT(*)::int AS policy_count
      FROM pg_policies
      WHERE schemaname = 'public'
      GROUP BY tablename
    SQL
    policies_by_table = policy_rows.each_with_object({}) do |row, hash|
      hash[row['tablename']] = row['policy_count']
    end
    tables_with_full_policies = policies_by_table.select { |_, c| c >= 4 }.keys.sort

    # 项目是否启用 RLS 路线（有任一张业务表有 policy）
    rls_project = policies_by_table.any?

    errors = []
    warnings = []

    # 1. 模型注册了 concern 但表里没 data_version 列
    missing_column = registered_tables - db_tables_with_column
    missing_column.each do |t|
      errors << "Model for table '#{t}' includes DataVersionable but table has no `data_version` column"
    end

    # 2. 表有 data_version 列但模型没 include concern（或是系统表但忘了 data_version_excluded!）
    not_registered = db_tables_with_column - registered_tables
    not_registered.each do |t|
      # 检查是否是"模型存在但用 data_version_excluded! 排除了"的系统表场景
      all_models_for_table = DataVersionable.models.select { |m| m.table_name == t }
      excluded = all_models_for_table.any? { |m| DataVersionable.excluded_models.include?(m) }

      if excluded
        # 已在模型层显式排除（系统表场景），降级为 warning 并建议清掉列
        warnings << "Table '#{t}' has `data_version` column but its model uses data_version_excluded! " \
                    '(system table). The column is dead weight — consider dropping it via migration ' \
                    "(`remove_column :#{t}, :data_version`). See ADR-003."
      elsif all_models_for_table.empty?
        # 真·孤儿表：表存在但没任何模型
        errors << "Table '#{t}' has `data_version` column but no model is registered for it. " \
                  'Either this is an orphan table (drop it) or a model needs to `include DataVersionable` ' \
                  "(which ApplicationRecord does automatically). \n" \
                  "    Fix: `rails g migration Drop#{t.camelize}` or check app/models/#{t.singularize}.rb"
      else
        # 有模型但没 include concern（现在几乎不会发生，因为 ApplicationRecord 自动 include）
        errors << "Table '#{t}' has `data_version` column but its model(s) " \
                  "[#{all_models_for_table.map(&:name).join(', ')}] do NOT include DataVersionable. " \
                  'This will cause default_scope to fail and writes to bypass set_data_version callback. ' \
                  'Ensure the model inherits from ApplicationRecord.'
      end
    end

    # 3. 表有 data_version 列但 RLS policy 数量 < 4
    missing_policies = db_tables_with_column - tables_with_full_policies
    missing_policies.each do |t|
      count = policies_by_table[t] || 0
      msg = "Table '#{t}' has `data_version` column but only #{count} RLS policy(ies), expected 4 " \
            '(select/insert/update/delete).'
      if rls_project
        errors << "#{msg} Run `rails g rls_policy #{t}` to backfill."
      else
        warnings << "#{msg} (Project does not use RLS — ok if you rely on application-level default_scope only.)"
      end
    end

    # 4. 有 RLS policy 但表没 data_version 列（多余的 policy）
    extra_policies = tables_with_full_policies - db_tables_with_column
    extra_policies.each do |t|
      warnings << "Table '#{t}' has RLS policies but no `data_version` column (orphan policy?)"
    end

    # 输出
    puts "  Registered models  : #{registered_tables.size}"
    puts "  Tables w/ column   : #{db_tables_with_column.size}"
    puts "  Tables w/ 4 polices: #{tables_with_full_policies.size}"
    puts "  RLS enabled?       : #{rls_project ? 'yes' : 'no (application-layer only)'}"
    puts ''

    if errors.empty? && warnings.empty?
      puts "  ✅ All aligned.\n\n"
      next
    end

    errors.each   { |e| puts "  ✗ ERROR:   #{e}" }
    warnings.each { |w| puts "  ⚠ WARNING: #{w}" }
    puts ''

    exit 1 if errors.any?
  end
end
