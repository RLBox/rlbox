RSpec.configure do |config|
  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)

    # Load baseline data from data_packs (data_version='0')
    # This is the canonical way to load test fixtures in this project.
    # Do NOT use db/seeds.rb for test data — use app/validators/support/data_packs/
    begin
      data_packs_dir = Rails.root.join('app/validators/support/data_packs')
      pack_files = Dir.glob(data_packs_dir.join('**/*.rb')).sort

      unless pack_files.empty?
        # Set session variable so DataVersionable writes data_version='0'
        ActiveRecord::Base.connection.execute("SET SESSION app.data_version = '0'")

        # base.rb loads first, then alphabetical
        base_file = pack_files.find { |f| File.basename(f) == 'base.rb' }
        if base_file
          pack_files.delete(base_file)
          pack_files.unshift(base_file)
        end

        pack_files.each { |f| load f }
      end
    rescue => e
      puts "\n⚠️  Data packs loading failed: #{e.message}"
    end
  end

  config.before(:each) do
    DatabaseCleaner.strategy = :transaction
  end

  config.before(:each) do
    DatabaseCleaner.start
  end

  config.append_after(:each) do
    DatabaseCleaner.clean
  end
end
