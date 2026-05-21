# frozen_string_literal: true

require_relative "fedex_rest_client/version"

require_relative "fedex_rest_client/credential"
require_relative "fedex_rest_client/client"


module FedexRestClient
  class Error < StandardError; end
  class ApiError < StandardError; end
  class AuthError < StandardError; end
  class ConnectionError < StandardError; end
  class RefreshTokenError < StandardError; end
  class TokenExpirationError < StandardError; end
  class RateLimitError < StandardError; end
end
