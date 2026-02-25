# frozen_string_literal: true

# V001CreatePostValidator
#
# Demo validator: asks the user (or AI agent) to create a post titled "Hello World"
# with status "published".
#
# Demonstrates:
#   - requires_ui: enforces that the frontend form exposes status=[draft,published]
#   - data_version isolation: created post is scoped to this session only
#   - add_assertion: RSpec-style weighted assertions
#
class V001CreatePostValidator < BaseValidator
  self.validator_id   = 'v001_create_post'
  self.title          = '在系统中创建一篇帖子'
  self.description    = '请创建一篇标题为"Hello World"、状态为"published"的帖子。'
  self.timeout_seconds = 60

  # Declares that this validator requires the frontend to expose status=[draft,published].
  # If _form.html.erb doesn't have the annotation, execute_prepare raises
  # BaseValidator::UiCapabilityMissingError before any test data is created.
  requires_ui :posts, :title, :body, status: %i[draft published]

  def prepare
    # Baseline data (e.g. users) is already loaded by the initializer.
    # Nothing extra to set up for this simple validator.
    {}
  end

  def verify
    add_assertion('A post titled "Hello World" exists', weight: 50) do
      post = Post.find_by(title: 'Hello World')
      expect(post).not_to be_nil
    end

    add_assertion('Post status is "published"', weight: 50) do
      post = Post.find_by(title: 'Hello World')
      expect(post&.status).to eq('published')
    end
  end

  # Used by execute_simulate (automated regression mode).
  def simulate
    user = User.first
    raise 'No users in baseline data — add a data pack to app/validators/support/data_packs/' unless user

    Post.create!(
      title:  'Hello World',
      status: 'published',
      body:   'Created by V001CreatePostValidator simulate.',
      user:   user
    )

    { message: 'Created post "Hello World" with status "published".' }
  end
end
