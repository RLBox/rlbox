# frozen_string_literal: true

namespace :images do
  def load_helper
    require Rails.root.join('app/helpers/image_seed_helper')
  end

  # ---------------------------------------------------------------------------
  # images:seed
  # Download all seed images from Unsplash to public/images/.
  # Run once after cloning, and again whenever new categories are added.
  # ---------------------------------------------------------------------------
  desc 'Download all seed images to public/images/'
  task seed: :environment do
    load_helper

    puts "\n=== Downloading Seed Images ===\n\n"

    ImageSeedHelper::UNSPLASH_IMAGE_IDS.each_key do |category|
      ImageSeedHelper.download_category_images(category)
    end

    puts "\n  Done.\n\n"
  end

  # ---------------------------------------------------------------------------
  # images:seed_category[category]
  # Download images for a single category, e.g. rake images:seed_category[covers]
  # ---------------------------------------------------------------------------
  desc 'Download seed images for one category (e.g. rake images:seed_category[covers])'
  task :seed_category, [:category] => :environment do |_t, args|
    load_helper

    unless args[:category]
      puts "Usage: rake images:seed_category[category]"
      puts "Available: #{ImageSeedHelper::UNSPLASH_IMAGE_IDS.keys.join(', ')}"
      exit 1
    end

    category = args[:category].to_sym

    unless ImageSeedHelper::UNSPLASH_IMAGE_IDS.key?(category)
      puts "Unknown category: #{category}"
      puts "Available: #{ImageSeedHelper::UNSPLASH_IMAGE_IDS.keys.join(', ')}"
      exit 1
    end

    ImageSeedHelper.download_category_images(category)
    puts "  Done.\n\n"
  end

  # ---------------------------------------------------------------------------
  # images:status
  # Show download status for all categories.
  # ---------------------------------------------------------------------------
  desc 'Show seed image download status'
  task status: :environment do
    load_helper

    puts "\n=== Seed Image Status ===\n\n"

    ImageSeedHelper::UNSPLASH_IMAGE_IDS.each do |category, ids|
      downloaded = ids.each_with_index.count do |_, i|
        singular = category.to_s.chomp('s')
        Rails.root.join('public', 'images', category.to_s, "#{singular}_#{i + 1}.jpg").exist?
      end

      icon = downloaded == ids.size ? '✓' : '✗'
      puts "  #{icon} #{category.to_s.ljust(15)} #{downloaded}/#{ids.size}"
    end

    puts "\n  Run 'rake images:seed' to download missing images.\n\n"
  end

  # ---------------------------------------------------------------------------
  # images:clean
  # Remove all downloaded seed images from public/images/.
  # ---------------------------------------------------------------------------
  desc 'Remove all downloaded seed images'
  task clean: :environment do
    load_helper

    puts "\n=== Cleaning Seed Images ===\n\n"
    ImageSeedHelper.clean_all
    puts "\n  Done.\n\n"
  end

  # ---------------------------------------------------------------------------
  # images:clean_category[category]
  # Remove images for one category, e.g. rake images:clean_category[covers]
  # ---------------------------------------------------------------------------
  desc 'Remove seed images for one category (e.g. rake images:clean_category[covers])'
  task :clean_category, [:category] => :environment do |_t, args|
    load_helper

    unless args[:category]
      puts "Usage: rake images:clean_category[category]"
      exit 1
    end

    ImageSeedHelper.clean_category(args[:category].to_sym)
    puts "  Done.\n\n"
  end
end
