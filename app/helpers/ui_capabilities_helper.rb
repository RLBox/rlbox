# frozen_string_literal: true

# UiCapabilitiesHelper
#
# Provides a `ui_select` form helper that reads available values from the
# UiCapabilities registry (derived from <%# ui_supports: %> annotations).
#
# Usage in views:
#   <%= ui_select form, :status, :posts %>
#
# This renders a <select> containing only the status values that are explicitly
# declared in app/views/posts/_form.html.erb via:
#   <%# ui_supports: status=[draft,published] %>
#
# If no annotation exists for the field, an empty select is rendered
# and a warning comment is inserted into the HTML for debugging.
module UiCapabilitiesHelper
  # Render a <select> for +field+ restricted to the values declared via ui_supports:
  # in the _form.html.erb for +resource+.
  #
  # @param form      [ActionView::Helpers::FormBuilder]
  # @param field     [Symbol]  model attribute name
  # @param resource  [Symbol]  resource name matching the view directory
  #                            (e.g. :posts for app/views/posts/)
  # @param options   [Hash]    passed through to form.select (include_blank, prompt, etc.)
  # @param html_options [Hash] HTML attributes passed to form.select
  def ui_select(form, field, resource, options = {}, html_options = {})
    values = UiCapabilities.values_for(resource, field)

    if values.nil? || values.empty?
      # Surfaced as an HTML comment to aid debugging; does not raise in production
      return content_tag(:span, nil, class: 'ui-select-unavailable',
        data: { resource: resource, field: field }) do
        concat "<!-- ui_select: no ui_supports annotation found for #{resource}.#{field} -->"
      end
    end

    choices = values.map { |v| [v.humanize, v] }
    form.select(field, choices, options, html_options)
  end
end
