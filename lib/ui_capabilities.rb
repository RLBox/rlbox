# frozen_string_literal: true

# UiCapabilities
#
# Tracks which field values are actually exposed in the frontend.
# Source of truth is ERB annotation comments in view files:
#
#   <%# ui_supports: status=[draft,published] delivery_type=[mail] %>
#
# The scanner derives the resource name from the view path:
#   app/views/posts/_form.html.erb  →  resource: "posts"
#   app/views/visa_orders/_form.html.erb  →  resource: "visa_orders"
#
# Usage in validators:
#   class V001CreatePostValidator < BaseValidator
#     requires_ui :posts, status: [:draft, :published]
#   end
#
module UiCapabilities
  # Annotation format: <%# ui_supports: field1=[v1,v2] field2=[v3] %>
  ANNOTATION_PATTERN = /<%#\s*ui_supports:\s*(.+?)(?:\s*%>|\s*$)/

  # ── Registry ──────────────────────────────────────────────────────────────

  def self.registry
    @registry ||= {}
  end

  def self.reset!
    @registry = {}
    @scanned = false
  end

  # Returns true if the frontend declares support for resource.field=value.
  def self.supports?(resource, field, value)
    ensure_scanned!
    values = registry.dig(resource.to_s, field.to_s)
    return false unless values
    values.include?(value.to_s)
  end

  # Returns all declared values for a resource+field, or nil if not declared.
  def self.values_for(resource, field)
    ensure_scanned!
    registry.dig(resource.to_s, field.to_s)
  end

  # Returns the full registry (scans if needed).
  def self.all
    ensure_scanned!
    registry
  end

  # ── Scanner ───────────────────────────────────────────────────────────────

  # Scan all _form.html.erb files under app/views/ and populate the registry.
  # Called lazily the first time a lookup is made.
  def self.scan_views!(root = Rails.root)
    @registry = {}

    form_files = Dir.glob(root.join('app/views/**/_form.html.erb'))
    form_files.each do |path|
      resource = extract_resource_name(path, root)
      next unless resource

      File.foreach(path) do |line|
        match = line.match(ANNOTATION_PATTERN)
        next unless match

        parse_annotation(match[1]).each do |field, values|
          @registry[resource] ||= {}
          @registry[resource][field] = values
        end
      end
    end

    @scanned = true
    @registry
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  def self.ensure_scanned!
    scan_views! unless @scanned
  end

  # Derive resource name from view path.
  # app/views/posts/_form.html.erb  →  "posts"
  # app/views/visa_orders/_form.html.erb  →  "visa_orders"
  def self.extract_resource_name(path, root)
    rel = Pathname.new(path).relative_path_from(root.join('app/views')).to_s
    parts = rel.split('/')
    return nil if parts.length < 2
    parts[-2]  # directory name = resource
  end

  # Parse "status=[draft,published] delivery_type=[mail]" into a Hash.
  def self.parse_annotation(str)
    result = {}
    str.scan(/(\w+)=\[([^\]]*)\]/) do |field, values_str|
      result[field] = values_str.split(',').map(&:strip).reject(&:empty?)
    end
    result
  end
  private_class_method :ensure_scanned!, :extract_resource_name, :parse_annotation
end
