require 'rails_helper'

RSpec.describe "Database Seeds" do
  let(:seeds_file) { Rails.root.join('db/seeds.rb') }
  let(:data_packs_dir) { Rails.root.join('app/validators/support/data_packs') }

  it "data packs are the canonical source of baseline data" do
    # This project uses data_packs (app/validators/support/data_packs/) for baseline data,
    # NOT db/seeds.rb. Baseline data is loaded via `rake validator:reset_baseline`.
    pack_files = Dir.glob(data_packs_dir.join('**/*.rb'))

    expect(pack_files).not_to be_empty,
      "Expected data packs in app/validators/support/data_packs/ but none found. " \
      "Add .rb files there to define baseline data (data_version='0')."
  end

  it "seeds.rb does not contain test user data" do
    seeds_content = File.read(seeds_file)
    code_lines = seeds_content.lines.reject { |line| line.strip.empty? || line.strip.start_with?('#') }

    # seeds.rb should not duplicate test data that belongs in data_packs
    has_user_create = code_lines.any? { |line| line.match?(/User\.(create|find_or_create)/) }
    expect(has_user_create).to be_falsey,
      "db/seeds.rb should NOT contain User.create calls. " \
      "Test/baseline user data belongs in app/validators/support/data_packs/."
  end
end
