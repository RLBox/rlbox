# frozen_string_literal: true

# DataPackValidator — validates data pack integrity after loading.
#
# Design principles:
#   1. Auto-scans data pack files — no manual configuration required.
#   2. Reads schema version from db/schema.rb to detect database changes.
#   3. Convention-based validation rules derived from NOT NULL constraints.
#
# What is validated:
#   - Which models are created in each data pack (inferred from file content)
#   - All baseline records have data_version = '0'
#   - No required (NOT NULL) columns contain NULL or empty values (3-record sample)
#
# SCHEMA VERSION GUARD
#   VALIDATED_SCHEMA_VERSION must match the current db/schema.rb version.
#   When the schema changes, validation logic may be stale (new columns unchecked,
#   removed columns still checked). Update this constant after reviewing the diff.
#
# Usage:
#   validator = DataPackValidator.new
#   results   = validator.validate_all
#   puts results.inspect

class DataPackValidator
  attr_reader :errors, :warnings, :schema_version, :last_validated_version

  # Update this constant whenever db/schema.rb changes.
  VALIDATED_SCHEMA_VERSION = '2026_02_24_074356'

  def initialize
    @errors                = []
    @warnings              = []
    @schema_version        = extract_schema_version
    @last_validated_version = VALIDATED_SCHEMA_VERSION
  end

  def schema_changed?
    return true if @last_validated_version.nil?
    @schema_version != @last_validated_version
  end

  # Validate all data packs.
  # Returns a hash:
  #   {
  #     all_passed:     true/false,
  #     pack_count:     Integer,
  #     passed_count:   Integer,
  #     failed_count:   Integer,
  #     schema_version: String,
  #     schema_changed: false,
  #     packs: {
  #       "pack_name.rb" => { passed: true/false, models: [...], error_count: N, errors: [...] }
  #     }
  #   }
  def validate_all
    if schema_changed?
      puts "\n⚠️  Schema has changed — validation script may be stale!"
      puts "   Script version: #{@last_validated_version}"
      puts "   Current schema: #{@schema_version}"
      puts "\n   Update VALIDATED_SCHEMA_VERSION in lib/data_pack_validator.rb"
      puts "   after reviewing the schema diff, then re-run.\n"
      exit 1
    end

    results = {
      all_passed:     true,
      pack_count:     0,
      passed_count:   0,
      failed_count:   0,
      schema_version: @schema_version,
      schema_changed: false,
      packs:          {}
    }

    data_pack_files.each do |file_path|
      pack_name   = Pathname.new(file_path).relative_path_from(Rails.root).to_s
      pack_result = validate_data_pack(file_path)

      results[:packs][pack_name] = pack_result
      results[:pack_count] += 1

      if pack_result[:passed]
        results[:passed_count] += 1
      else
        results[:failed_count] += 1
        results[:all_passed]    = false
      end
    end

    results
  end

  # Validate a single data pack file.
  def validate_data_pack(file_path)
    errors      = []
    models_info = []

    models = infer_models_from_file(file_path)

    if models.empty?
      return {
        passed:      false,
        models:      [],
        error_count: 1,
        errors:      ["No model insert statements found (insert_all / create / find_or_create_by)"]
      }
    end

    models.each do |model_name|
      begin
        model_class  = model_name.constantize
        model_errors = validate_model(model_class)

        models_info << {
          name:   model_name,
          count:  model_class.unscoped.where(data_version: '0').count,
          errors: model_errors
        }

        errors.concat(model_errors)
      rescue NameError => e
        errors << "Model #{model_name} does not exist: #{e.message}"
      rescue StandardError => e
        errors << "Error validating #{model_name}: #{e.message}"
      end
    end

    { passed: errors.empty?, models: models_info, error_count: errors.size, errors: errors }
  end

  private

  def data_pack_files
    Dir.glob(Rails.root.join('app/validators/support/data_packs/**/*.rb')).sort
  end

  def extract_schema_version
    schema_file = Rails.root.join('db/schema.rb')
    return nil unless File.exist?(schema_file)

    content = File.read(schema_file)
    match   = content.match(/ActiveRecord::Schema\[\d+\.\d+\]\.define\(version:\s*([\d_]+)\)/)
    match ? match[1] : nil
  end

  # Infer which models are written to by scanning for common ActiveRecord write patterns.
  def infer_models_from_file(file_path)
    content  = File.read(file_path)
    patterns = [
      /([A-Z][a-zA-Z0-9:]+)\.insert_all/,
      /([A-Z][a-zA-Z0-9:]+)\.create[!( ]/,
      /([A-Z][a-zA-Z0-9:]+)\.find_or_create_by/,
      /([A-Z][a-zA-Z0-9:]+)\.where.*\.update_all/
    ]

    models = patterns.flat_map { |p| content.scan(p).flatten }
    models.uniq.reject { |m| system_model?(m) || non_model_class?(m) }
  end

  def system_model?(model_name)
    %w[Administrator AdminOplog Session ValidatorExecution
       ActiveStorage::Blob ActiveStorage::Attachment ActiveStorage::VariantRecord].include?(model_name)
  end

  def non_model_class?(model_name)
    %w[BCrypt Password Date Time DateTime String Integer Float Array Hash
       File Dir JSON YAML Rails ActiveRecord ActiveSupport ActionCable
       DataVersionable].include?(model_name)
  end

  # Validate a single model's baseline data.
  def validate_model(model_class)
    errors = []

    unless model_class.column_names.include?('data_version')
      errors << "#{model_class.name} is missing the data_version column"
      return errors
    end

    records = model_class.unscoped.where(data_version: '0')

    if records.count == 0
      errors << "#{model_class.name} has no baseline records (data_version='0')"
      return errors
    end

    # Sample 3 records and check all NOT NULL columns
    required_columns = model_class.columns
      .reject { |col| col.null || col.name.match?(/\A(id|created_at|updated_at)\z/) }
      .map(&:name)

    records.limit(3).each_with_index do |record, idx|
      required_columns.each do |col|
        value = record.send(col)
        if value.nil? || (value.respond_to?(:empty?) && value.empty?)
          errors << "#{model_class.name} record ##{idx + 1} (id=#{record.id}) has blank required column: #{col}"
        end
      end
    end

    errors
  rescue StandardError => e
    ["#{model_class.name} validation error: #{e.message}"]
  end
end
