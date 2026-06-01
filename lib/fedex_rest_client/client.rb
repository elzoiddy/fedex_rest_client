

module FedexRestClient
  class Client
    include HTTParty

    attr_accessor :credential, :max_retries
    attr_reader :create_shipment_endpoint, :track_status_endpoint, :fedex_restapi_url
    attr_reader :retries
    attr_accessor :logger

    ##
    # creates new fedex resetful client
    # @parmas [ hash ] options - list of options for client
    # options:
    #   logger - logger, default to STDOUT logger
    #   fedex_credentails: - one instance of fedex credential object
    #   fedex_restapi_url: - fedex endpoint, default to sandbox
    #   max_retrues: -  number of retries client will attempt to make when errors occurs.
    #
    def initialize(options)
      @logger = options[:logger] || ::Logger.new(STDOUT)
      # get any tokens passed in directly
      @credential = options[:credential]

      @create_shipment_endpoint = 'ship/v1/shipments'
      @track_status_endpoint = 'track/v1/trackingnumbers'
      # default to development sandbox
      @fedex_restapi_url = options[:fedex_restapi_url] || 'https://apis-sandbox.fedex.com'

      @retries = 0
      # retry failed request at most 1 more time
      @max_retries = options[:max_retries] || 2
    end

    def refresh_token!
      # update token and update in memory copy
      if !credential.nil?
        token = self.get_api_token(credential.api_key, credential.api_secret)

        if token && !token["access_token"].nil?
          credential.token_expire_at = Time.at(token["expires_in"].to_i + Time.now.to_i)
          credential.oauth_token = token["access_token"]
          return true
        end
      end
      return false
    end

    ##
    # get token with API key and secret
    #
    # curl -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "grant_type=client_credentials&client_id=xxx&client_secret=yyy" https://apis-sandbox.fedex.com/oauth/token
    #
    # api_key and api_secret must be passed in
    def get_api_token(api_key, api_secret)

      header = {
        'Content-Type' => 'application/x-www-form-urlencoded'
      }
      body = {
        grant_type: "client_credentials", # for external callers of Fedex apis
        client_id: api_key,
        client_secret: api_secret
      }

      # straight up http post with form data
      result = fedex_post("oauth/token", header, body, {convert_data: false})
      # return the access token
      result
    rescue => exp
      logger.error(exp)
      {error_message: exp.message}
    end

    def address_resolution(address)
      # not yet implemented
      true
    end

    ##
    # Check to see if credentials given given needs a refresh
    #

    def need_token_refresh?
      credential.oauth_token.nil? ||
        credential.token_expire_at.nil? ||
        credential.token_expire_at.to_i < Time.now.to_i
    end

    def fedex_shipping_label(args)
      if need_token_refresh?
        if !refresh_token!
          # failed to refresh token
          raise RefreshTokenError.new("Unable to refresh token")
        end
      end

      label_request = create_label(args)
      result = fedex_post(create_shipment_endpoint, header_with_bearer_token, label_request)

      shipment_response = result.dig("output", "transactionShipments").first["pieceResponses"]
      transaction_id = result.dig("transactionId")
      label = shipment_response.first["packageDocuments"].first
      tracking_number = shipment_response.first["trackingNumber"]

      # transaction id for debugging later.
      {tracking_number: tracking_number, image64: label['encodedLabel'], transaction_id: transaction_id}
    rescue => exp
      logger.error(exp)
    end

    private

    # convert structure to fedex name and fields
    def create_label(args)
      # sender details
      from_name                  = args[:from_name]
      from_address               = args[:from_address]
      from_phone                 = args[:from_phone]

      # recipent details
      to_name                    = args[:to_name]
      to_company                 = args[:to_attn]
      to_phone                   = args[:to_phone]
      to_address                 = args[:to_address]

      package_weight             = args[:package_weight]
      package_weight_unit        = args[:package_weight_unit] || "LB"

      # shipment details
      service_type               = args[:service_type]
      label_format               = args[:label_format]
      label_stock_type           = args[:label_stock_type]
      label_rotation             = args[:label_rotation].nil? ? args[:label_rotation] : "NONE"
      return_label               = args[:return_label]
      bill_third_party           = args[:bill_third_party].nil? ? false : true
      third_party_account_number = args[:third_party_account_number]
      residential_recipient      = args[:residential_recipient].nil? ? false : true

      # construct payload body

      shipper = {
        :contact => {
            :personName   => from_name,
            :companyName  => from_address[:company],
            :phoneNumber  => from_phone,
        },
        :address => {
            :streetLines        => address_street(from_address[:address1], from_address[:address2]),
            :city               => from_address[:city],
            :stateOrProvinceCode=> from_address[:state_abbr],
            :postalCode         => from_address[:zipcode],
            :countryCode        => from_address[:country_iso],
        }
      }

      recipients = []
      recipients << {
        :contact => {
            :personName   => to_name,
            :companyName  => to_company || to_address[:company],
            :phoneNumber  => to_phone,
        },
        :address => {
            :streetLines         => address_street(to_address[:address1], to_address[:address2]),
            :city                => to_address[:city],
            :stateOrProvinceCode => to_address[:state_abbr],
            :postalCode          => to_address[:zipcode],
            :countryCode         => to_address[:country_iso],
            :residential         => residential_recipient,
        },
      }

      packages = []
      packages << {
        :weight => {:units => package_weight_unit, :value => package_weight},
      }

      label_options = {
        :imageType      => label_format,
        :labelStockType => label_stock_type,
        :labelRotation  => label_rotation
      }

      requested_shipment = {
        :shipper                   => shipper,
        :recipients                => recipients,
        :serviceType               => service_type,
        :packagingType             => "YOUR_PACKAGING",
        :pickupType                => "USE_SCHEDULED_PICKUP",
        :shippingChargesPayment    => {:paymentType => "SENDER"},
        :labelSpecification        => label_options,
        :requestedPackageLineItems => packages
      }

      if bill_third_party
        requested_shipment[:shippingChargesPayment] = {
          :paymentType => "THIRD_PARTY",
          :payor => {
            :responsibleParty => {
                :accountNumber => {
                  :value => "#{third_party_account_number}"
                }
              }
          }
        }
      end

      shipment_special_services = nil
      if return_label
        shipment_special_services = {
          :specialServiceTypes => ["RETURN_SHIPMENT"],
          :returnShipmentDetail => {
            :returnType => "PRINT_RETURN_LABEL"
          }
        }
      end

      if !shipment_special_services.nil?
        requested_shipment[:shipmentSpecialServices] = shipment_special_services
      end

      #Create the hash for the shipping-request
      label_request = {
        :mergeLabelDocOption  => "LABELS_ONLY",
        :labelResponseOptions => "LABEL",
        :requestedShipment    => requested_shipment,
        :accountNumber        => {
          :value => credential.account_number
        }
      }

      label_request
    end

    # combine address1 and address2 to array of lines
    def address_street(address1, address2)
      address = [address1]
      address << address2 if !address2.nil?
      address
    end

    def header_with_bearer_token
      {
        'Authorization' => "Bearer #{credential.oauth_token}",
        'Accept'        => "application/json",
        'Content-Type'  => "application/json"
      }
    end

    ##
    # Notifies the fedex endpoint to perform the specified action (i.e. "CreateShioment", or "CancelShipment")
    # according to the specified data
    #
    # @param [ String ] endpoint - teh endpoint for the Fedex REST API call
    # @param [ Hash ] header - header for the REST call to the endpoint
    # @param [ Hash ] data - a hash of object data informing the endpoint
    # @param [ Hash ] options - optional flags controlling submission, but not sent to fedex
    # @return [ Hash ] response


    def fedex_post(end_point, header, data, options={})
      # convert data JSON format before sending
      convert_data = options[:convert_data].nil? ? true : options[:convert_data]
      # verbose mode
      verbose      = options[:verbose] || false

      headers      = header || {}
      result       = nil

      body_data = convert_data ? data.to_json : data

      request_data = {
        base_uri: @fedex_restapi_url,
        headers:  headers,
        body:     body_data
      }

      begin
        if verbose
          logger.info("making request POST /#{end_point} with #{request_data}")
        end
        response = self.class.post("/#{end_point}", request_data)

      rescue Exception => e
        logger.error(e.message)
        if verbose
          log.error(e.backtrace.join("\n"))
        end
        raise
      end

      result = JSON.parse(response.body)
      transaction_id = result.dig("transactionId")
      if !transaction_id.nil?
        logger.info("Fedex response transaction_id:#{transaction_id}")
      end

      # handle success
      if response.code >= 200 && response.code <= 299
        # reset retries after each successful request
        @retries = 0
        return result
      else
        error_msg = result["error_description"] || result["message"] || result["errors"]
        if verbose
          logger.error("error_msg: #{error_msg}")
        end
      end

      # check token expiration specifically here to retry
      # {"error"=>"invalid_request", "error_description"=>"CXS JWT is expired"}
      # {"error"=>"invalid_request", "error_description"=>"We could not authenticate your credentials. Please try again"}

      if response.code == 401 ||
          error_msg.to_s =~ /JWT is expired/ ||
          error_msg.to_s =~ /could not authenticate/i
        logger.info("Unauthenticated during post, refreshing token")

        # retry again if we successfully refresh
        if (@retries += 1) < max_retries
          if refresh_token!
            # update new header and call again.
            header['Authorization'] = "Bearer #{credential.oauth_token}"
            return fedex_post(end_point, header, data, options)
          else
            # refresh token failed
            raise RefreshTokenError.new("Unable to refresh token")
          end
        else
          # too many retries
          raise TokenExpirationError.new("Token expired, max retries attempted, giving up!")
        end
      else
        # handle other errors
        # look for specific codes here
        handle_specific_errors(response)
        # unable to handle the specific errors we are looking for
        logger.error(response.body)
        raise ApiError.new("API error from fedex")
      end

    end

    def handle_specific_errors(response)
      result = JSON.parse(response.body) rescue {}

      if response.code == 429
        # rate limitted
        begin
          error_msg = result.dig("errors") || result.dig("message")
        rescue Exception => e
          logger.error(response.body.inspect)
          error_msg = "Rate limit error."
        end
        raise RateLimitError.new(error_msg)
      elsif response.code == 401
        logger.error(response.body.inspect)
        raise AuthError.new("Unauthorized")
      elsif response.code == 500
        logger.error(response.body.inspect)
        raise ConnectionError.new("Fedex Service Failure")
      elsif response.code == 503
        logger.error(response.body.inspect)
        raise ConnectionError.new("Fedex Service Unavailable")
      end

    end

  end

end