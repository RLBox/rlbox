# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# IMPORTANT: Do NOT add Administrator data here!
# Administrator accounts should be created manually by user.
# This seeds file is only for application data (products, categories, etc.)
#
require 'open-uri'

# Write your seed data here

# Create some sample users for testing
puts "Creating sample users..."
unless User.exists?(email: 'demo@rlbox.com')
  User.create!(
    name: 'Demo User',
    email: 'demo@rlbox.com',
    password: 'password',
    verified: true
  )
  puts "✓ Created demo user (demo@rlbox.com / password)"
end

puts "✓ Seeds completed successfully!"
