module FedexRestClient
  class Credential
    ## simple util class that holds
    # api_key
    # api_secret
    # oauth token
    # oauth token expiration - seconds since EPOCH
    # account_number
    # you probably want to make this an active record backed up by a database table
    # in your implementation

    attr_accessor :api_key, :api_secret, :account_number, :oauth_token, :token_expire_at

    def initialize(api_key, api_secret, account_number)
      # These 3 you definiately need to acquire access
      @api_key = api_key
      @api_secret = api_secret
      @account_number = account_number
    end

  end
end
