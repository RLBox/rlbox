# frozen_string_literal: true

# UiCapabilities Convention Spec
#
# Ensures every `requires_ui` declaration in any BaseValidator subclass is
# actually satisfied by a `ui_supports:` ERB annotation in the corresponding
# _form.html.erb view.
#
# This is the CI guard that catches the "partial frontend implementation" problem:
# a developer creates a validator for a field value (e.g. delivery_type=pickup)
# that the frontend never rendered.
#
# To fix a failure:
#
#   Scenario A — the frontend DOES support this value; just add the annotation:
#     In app/views/<resource>/_form.html.erb, add or extend:
#       <%# ui_supports: field=[value1,value2] %>
#
#   Scenario B — the frontend does NOT support this value (yet):
#     Remove the requires_ui declaration from the validator, or scope it to
#     values the frontend actually exposes.
#
RSpec.describe 'UiCapabilities convention' do
  before(:all) do
    # Load all validators so their requires_ui declarations are evaluated
    Dir[Rails.root.join('app/validators/**/*_validator.rb')].each { |f| require f }
    # Force UiCapabilities to (re-)scan views
    UiCapabilities.reset!
    UiCapabilities.scan_views!
  end

  it 'all requires_ui declarations are satisfied by current ui_supports: annotations' do
    validators = ObjectSpace.each_object(Class).select { |c| c < BaseValidator }

    failures = []
    validators.each do |validator_class|
      validator_class.ui_requirements.each do |req|
        next if UiCapabilities.supports?(req[:resource], req[:field], req[:value])

        failures << "#{validator_class.name}: #{req[:resource]}.#{req[:field]}=#{req[:value]}"
      end
    end

    expect(failures).to be_empty, <<~MSG
      The following validators declare requires_ui for values not found in any _form.html.erb:

        #{failures.join("\n  ")}

      Fix by choosing one of:

        A) The frontend supports this value — add/extend the annotation in the form view:
             <%# ui_supports: field=[value1,value2] %>

        B) The frontend does NOT support this value — remove the requires_ui declaration
           or wait until the frontend is implemented.
    MSG
  end
end
