# frozen_string_literal: true

# V001CreatePostValidator
#
# Demo validator: asks the user (or AI agent) to create a post titled "Hello World"
# with status "published".
#
# Demonstrates:
#   - data_version isolation: created post is scoped to this session only
#   - add_assertion: RSpec-style weighted assertions
#
class V001CreatePostValidator < BaseValidator
  self.validator_id   = 'v001_create_post'
  self.title          = 'Create a Post in the System'
  self.description    = 'Please create a post with title "Hello World" and status "published".'
  self.timeout_seconds = 60

  def prepare
    # Baseline data (e.g. users) is already loaded by the initializer.
    # Nothing extra to set up for this simple validator.
    {
      task: 'Create a post titled "Hello World" with status "published"',
      hint: 'Navigate to Posts section and create a new post'
    }
  end

  def verify
    add_assertion('A post titled "Hello World" exists', weight: 50) do
      post = Post.find_by(title: 'Hello World', data_version: @data_version)
      expect(post).not_to be_nil, 'No post with title "Hello World" found'
    end

    add_assertion('Post status is "published"', weight: 50) do
      post = Post.find_by(title: 'Hello World', data_version: @data_version)
      expect(post&.status).to eq('published'), 
        "Post status is incorrect. Expected: published, Actual: #{post&.status}"
    end
  end

  # Used by execute_simulate (automated regression mode).
  def simulate
    user = User.where(data_version: 0).first
    raise 'No users in baseline data' unless user

    Post.create!(
      title:  'Hello World',
      status: 'published',
      body:   'Created by V001CreatePostValidator simulate.',
      user:   user,
      data_version: @data_version
    )

    { message: 'Created post "Hello World" with status "published".' }
  end
end
