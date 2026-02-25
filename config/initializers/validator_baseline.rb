# frozen_string_literal: true

# Validator Baseline Data Initializer
#
# Loads baseline seed data (data_version='0') at application startup.
# Baseline data is shared by all validator sessions as read-only reference data.
#
# Data packs are plain Ruby files in app/validators/support/data_packs/
# that create records using idempotent patterns (find_or_create_by, upsert, etc.).
# base.rb is loaded first if present; remaining files are loaded alphabetically.
#
# This initializer is a no-op if the data_packs directory is empty or missing —
# add data pack files to opt in. Skipped entirely in the test environment.
#
Rails.application.config.after_initialize do
  next if Rails.env.test?

  begin
    data_packs_dir = Rails.root.join('app/validators/support/data_packs')
    pack_files = Dir.glob(data_packs_dir.join('**/*.rb')).sort

    if pack_files.empty?
      # No data packs yet — normal for a fresh template.
      # Add .rb files to app/validators/support/data_packs/ to load baseline data.
      next
    end

    # Ensure data_packs tables exist before running (guard against mid-migration startup)
    next unless ActiveRecord::Base.connection.table_exists?('validator_executions')

    # SET SESSION so DataVersionable's before_create hook writes data_version='0'
    ActiveRecord::Base.connection.execute("SET SESSION app.data_version = '0'")

    # Load base.rb first (foundation data), then the rest alphabetically.
    # Search within results so the file can live at any depth under data_packs/.
    base_file = pack_files.find { |f| File.basename(f) == 'base.rb' }
    if base_file
      pack_files.delete(base_file)
      pack_files.unshift(base_file)
    end

    Rails.logger.info "[ValidatorBaseline] Loading #{pack_files.size} data pack(s)..."

    pack_files.each do |file|
      filename = Pathname.new(file).relative_path_from(Rails.root).to_s
      begin
        load file
        Rails.logger.info "[ValidatorBaseline]   ✓ #{filename}"
      rescue StandardError => e
        Rails.logger.error "[ValidatorBaseline]   ✗ #{filename}: #{e.message}"
      end
    end

    Rails.logger.info "[ValidatorBaseline] Baseline data ready (data_version='0')"

  rescue StandardError => e
    Rails.logger.error "[ValidatorBaseline] Failed to load baseline data: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end
end
