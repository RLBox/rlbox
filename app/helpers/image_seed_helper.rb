# frozen_string_literal: true

require 'open-uri'
require 'fileutils'

# ImageSeedHelper — download Unsplash images for use in data packs and seeds.
#
# Problem: Direct Unsplash URLs (https://images.unsplash.com/...) cannot be
# used as image_url string column values because they depend on external network
# availability and may be rate-limited or unavailable at runtime.
#
# Solution: Download images locally at setup time, reference local paths.
#
# Setup (one-time, after cloning):
#   rake images:seed
#
# Usage in data packs (image_url string columns):
#   require_relative '../../../../../app/helpers/image_seed_helper'
#   Model.insert_all([{ name: 'X', image_url: ImageSeedHelper.random_image_from_category(:covers) }])
#
# Usage for ActiveStorage attachments:
#   Use URI.open in db/seeds.rb — not data packs. Data packs use insert_all with string URLs.
#
# Categories: :people, :products, :covers, :landscapes, :interiors

module ImageSeedHelper
  # Unsplash photo IDs (the segment after "photo-" in the URL).
  # Extend by adding more IDs to any category to grow the pool.
  UNSPLASH_IMAGE_IDS = {
    # Profile pictures, team photos
    people: %w[
      1507003211169-0a1dd7228f2d 1544005313-94ddf0286df2 1438761681033-6461ffad8d80
      1494790108377-be9c29b29330 1529626455-8f4cad9a8d9e 1535713875002-d1d0cf377fde
    ],
    # Generic product / item photos
    products: %w[
      1555881400-74d7acaacd8b 1533929736458-ca588d08c8be 1503454537195-1dcabb73ffb9
      1526170375885-4d8ecf77b99f 1505740420928-5e560c06d30e 1491553895911-0055eca6402d
    ],
    # Blog / article cover images
    covers: %w[
      1506905925346-21bda4d32df4 1464822759023-fed622ff2c3b 1519681393784-d120267933ba
      1523712999610-f77fbcfc3843 1476514525504-03b2457c5982 1469854523690-44d8caf40d3e
    ],
    # Outdoor, scenic, landscape photography
    landscapes: %w[
      1528360983277-13d401cdc186 1549080434-f43b99e80e2b 1506765515441-c3cfd8b7b0b7
      1501854140801-50d01698950b 1470770841072-f978cf4d019e 1462275646964-a0e3386b89fa
    ],
    # Room interiors, offices, spaces
    interiors: %w[
      1566073771259-6a8506099945 1542314831-068cd1dbfeeb 1551882547-ff40c63fe5fa
      1571003123894-1f0594d2b5d9 1582719478250-c89cae4dc85b 1549294413-26f195200c16
    ]
  }.freeze

  # ── Download helpers ────────────────────────────────────────────────────────

  # Download a single image to public/images/<category>/<category_N>.jpg.
  # Skips download if the file already exists.
  # Returns the local web path (e.g. "/images/covers/cover_1.jpg") or nil on failure.
  def self.download_image(category, index, unsplash_id)
    ensure_directory(category)

    singular = category.to_s.chomp('s')
    filename  = "#{singular}_#{index}.jpg"
    dir       = Rails.root.join('public', 'images', category.to_s)
    local     = dir.join(filename)

    return "/images/#{category}/#{filename}" if local.exist?

    url = "https://images.unsplash.com/photo-#{unsplash_id}?w=1200&q=80"
    URI.open(url) do |io|                    # rubocop:disable Security/Open
      local.binwrite(io.read)
    end
    puts "  ✓ #{filename}"
    "/images/#{category}/#{filename}"
  rescue StandardError => e
    puts "  ✗ #{filename}: #{e.message}"
    nil
  end

  # Download every image for a category. Returns array of local paths.
  def self.download_category_images(category)
    ids = UNSPLASH_IMAGE_IDS[category.to_sym]
    return [] if ids.blank?

    puts "Downloading #{category} (#{ids.size} images)..."
    ids.each_with_index.map { |id, i| download_image(category, i + 1, id) }.compact
  end

  # ── Lookup helpers ──────────────────────────────────────────────────────────

  # Return a random local web path from already-downloaded images for a category.
  # Returns nil if the category directory is empty (images not downloaded yet).
  def self.random_image_from_category(category)
    dir = Rails.root.join('public', 'images', category.to_s)
    return nil unless dir.exist?

    files = dir.glob('*.jpg').map { |f| f.basename.to_s }
    return nil if files.empty?

    "/images/#{category}/#{files.sample}"
  end

  # Return count random local paths (with repetition if pool is smaller than count).
  def self.random_images_from_category(category, count: 3)
    dir = Rails.root.join('public', 'images', category.to_s)
    return [] unless dir.exist?

    files = dir.glob('*.jpg').map { |f| f.basename.to_s }
    return [] if files.empty?

    Array.new(count) { "/images/#{category}/#{files.sample}" }
  end

  # Return all local web paths for a category (deterministic, sorted).
  def self.all_images_for_category(category)
    UNSPLASH_IMAGE_IDS[category.to_sym]&.each_with_index&.map do |_, i|
      singular = category.to_s.chomp('s')
      "/images/#{category}/#{singular}_#{i + 1}.jpg"
    end || []
  end

  # ── Status / cleanup ────────────────────────────────────────────────────────

  def self.category_downloaded?(category)
    ids = UNSPLASH_IMAGE_IDS[category.to_sym]
    return false if ids.blank?

    ids.each_with_index.all? do |_, i|
      singular = category.to_s.chomp('s')
      Rails.root.join('public', 'images', category.to_s, "#{singular}_#{i + 1}.jpg").exist?
    end
  end

  def self.clean_category(category)
    dir = Rails.root.join('public', 'images', category.to_s)
    FileUtils.rm_rf(dir) if dir.exist?
    puts "  ✓ Cleaned #{category}"
  end

  def self.clean_all
    dir = Rails.root.join('public', 'images')
    FileUtils.rm_rf(Dir.glob("#{dir}/*")) if dir.exist?
    puts "  ✓ All images cleaned"
  end

  private_class_method def self.ensure_directory(category)
    dir = Rails.root.join('public', 'images', category.to_s)
    FileUtils.mkdir_p(dir) unless dir.exist?
  end
end
