# frozen_string_literal: true

# ValidatorSessionBinder Middleware
#
# Purpose: Bind validator session_id from URL parameters to an independent cookie.
#
# Flow:
# 1. Client passes session_id via URL: http://SERVER/?session_id=xxx
# 2. This middleware extracts session_id from URL params
# 3. Stores it in an INDEPENDENT cookie: validator_session_id (NOT in Rails session)
# 4. ApplicationController#restore_validator_context reads from this cookie
#
# Why an independent cookie (not Rails session)?
# - Rails session is shared across all tabs in the same browser
# - Using session[:validator_execution_id] means opening multiple session_id URLs
#   in different tabs will cause them to overwrite each other
# - An independent cookie allows true multi-tab parallel validation
#
class ValidatorSessionBinder
  COOKIE_NAME = 'validator_session_id'

  def initialize(app)
    @app = app
  end

  def call(env)
    request = ActionDispatch::Request.new(env)

    # Extract session_id directly from query string
    # ⚠️ Don't use request.params — may not be parsed at middleware level
    query_params = Rack::Utils.parse_query(request.query_string)
    session_id = query_params['session_id']

    unless session_id.present?
      return @app.call(env)
    end

    Rails.logger.info "[ValidatorSessionBinder] Detected session_id=#{session_id} from URL param"

    # Call the app first so ApplicationController can run (may delete invalid cookie)
    status, headers, body = @app.call(env)

    # Remove all existing Set-Cookie headers for validator_session_id.
    # ApplicationController may have added a delete directive for an invalid cookie —
    # we must clear that before setting the new value.
    if headers['Set-Cookie']
      set_cookie_value = headers['Set-Cookie']

      cookie_lines = set_cookie_value.is_a?(Array) ? set_cookie_value : set_cookie_value.split("\n")
      remaining = cookie_lines.reject { |line| line.include?("#{COOKIE_NAME}=") }

      if remaining.empty?
        headers.delete('Set-Cookie')
      else
        headers['Set-Cookie'] = set_cookie_value.is_a?(Array) ? remaining : remaining.join("\n")
      end
    end

    # Clear any old cookie in the browser, then set the new value
    Rack::Utils.delete_cookie_header!(headers, COOKIE_NAME, { path: '/' })
    Rack::Utils.set_cookie_header!(headers, COOKIE_NAME, {
      value: session_id,
      path: '/',
      http_only: true,
      same_site: :lax,
      expires: Time.now + 24.hours
    })

    Rails.logger.info "[ValidatorSessionBinder] Set #{COOKIE_NAME}=#{session_id}"

    [status, headers, body]
  end
end
