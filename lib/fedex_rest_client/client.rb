

module FedexRestClient
  class Client
    include HTTParty

    attr_accessor :credential, :max_retries
    attr_reader :create_shipment_endpoint, :locations_endpoint, :track_status_endpoint, :address_valication_endpoint, :fedex_restapi_url
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

      @create_shipment_endpoint    = 'ship/v1/shipments'
      @locations_endpoint          = 'location/v1/locations'
      @address_valication_endpoint = "address/v1/addresses/resolve"
      @track_status_endpoint       = 'track/v1/trackingnumbers'
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


    # work in progress, use at your own risk
    # validate raw response if necessary

    def address_resolution(args)
      check_and_refresh_token

      valid_address = false
      corrected = false
      new_address = {}

      address_validation_request = create_address_validation_request(args)
      response = fedex_post(address_valication_endpoint, header_with_bearer_token, address_validation_request)

      resolved_address = response.dig("output", "resolvedAddresses")[0]
      # need to have at least 1 resolved address or else it's invalid
      if resolved_address != nil
        resolved_address_attr = resolved_address["attributes"]

        # see if address validated correctly

        # true is good or false is bad
        dpv_check = resolved_address_attr["DPV"] == true
        resolved_check = resolved_address_attr["Resolved"] == true
        # false or missing is good
        interpolated_check = resolved_address_attr["InterpolatedStreetAddress"] == nil ||
          resolved_address_attr["InterpolatedStreetAddress"] == false

        # validate state passed in is the same as the normalized one
        state_check = resolved_address["stateOrProvinceCode"].downcase == args[:state_abbr].downcase

        valid_address = dpv_check || resolved_check || state_check || interpolated_check

        # see if any of these attributes are corrected
        corrected = resolved_address["cityToken"][0]["changed"] ||
          resolved_address["stateOrProvinceCodeToken"]["changed"] ||
          resolved_address["postalCodeToken"]["changed"]

        new_address = {
          address1: resolved_address["streetLinesToken"][0],
          city: resolved_address["cityToken"][0]["value"],
          state_abbr: resolved_address["stateOrProvinceCode"],
          zipcode: format_zipcode(resolved_address["parsedPostalCode"]["base"], resolved_address["parsedPostalCode"]["addOn"]),
          country_iso: resolved_address["countryCode"]
        }
        if !resolved_address["streetLinesToken"][1].nil?
          new_address[:address2] = streetLinesToken["streetLinesToken"][1]
        end

      end

      output = {
        transaction_id: response['transactionId'],
        valid: valid_address,
        corrected: corrected,
        new_address: new_address,
        response: response
      }

      return output

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
      check_and_refresh_token

      label_request = create_label_request(args)
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

    def fedex_locations(args)
      check_and_refresh_token

      locations_request = create_locations_request(args)
      result = fedex_post(locations_endpoint, header_with_bearer_token, locations_request)

      result
    end

    private

    def format_zipcode(zipcode, addon)
      result = "#{zipcode}"
      if !addon.nil? && addon != ""
        result += "-#{addon}"
      end
      result
    end


    def check_and_refresh_token
      if need_token_refresh?
        if !refresh_token!
          # failed to refresh token
          raise RefreshTokenError.new("Unable to refresh token")
        end
      end
    end

    # query args for address validation query

    def create_address_validation_request(args)

      address1    = args[:address1]
      address2    = args[:address2]
      city        = args[:city]
      state_abbr  = args[:state_abbr]
      zipcode     = args[:zipcode]
      country_iso = args[:country_iso] || "US"


      validation_request = {
        validateAddressControlParameters: {
          includeResolutionTokens: true
        },
        addressesToValidate: [
          {
            address: {
              streetLines: [
                address1,
                address2,
              ],
              city: city,
              stateOrProvinceCode: state_abbr,
              postalCode: zipcode,
              countryCode: country_iso
            }
          }
        ]
      }

      validation_request
    end


    # query args for location query

    def create_locations_request(args)
      max_result            = args[:max_result] || 10
      result_distance_unit  = args[:result_distance_unit] || "MI" # or KM
      result_distance_value = args[:result_distance_value] || 25
      postal_code           = args[:zipcode]
      country_iso           = args[:country_iso] || "US"
      city                  = args[:city]
      state_abbr            = args[:state_abbr]
      latitude              = args[:latitude]
      longitude             = args[:longitude]

      location_types        = args[:location_types].nil? ? ["FEDEX_AUTHORIZED_SHIP_CENTER"] : args[:location_types]

      locations_request = {
        locationsSummaryRequestControlParameters: {
          distance: {
            units: result_distance_unit,
            value: result_distance_value
          },
          maxResults: max_result
        },
        locationSearchCriterion: "ADDRESS",
        location: {
          address: {
            city: city,
            stateOrProvinceCode: state_abbr,
            postalCode: postal_code,
            countryCode: country_iso,
            residential: false
          }
        },
        multipleMatchesAction: "RETURN_ALL",
        sort: {
          criteria: "DISTANCE",
          order: "ASCENDING"
        },
        sameState: false,
        sameCountry: true,
        locationTypes: location_types,
        includeHoliday: true
      }

      # add lat and long to request
      if !latitude.nil? && !longitude.nil?
        locations_request[:location][:longLat] = {
          latitude: latitude,
          longitude: longitude
        }
      end


      locations_request
    end

    # convert structure to fedex name and fields
    def create_label_request(args)
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
        logger.error(response.body)
        handle_specific_errors(response)
        # unable to handle the specific errors we are looking for
        raise ApiError.new("API error from fedex")
      end

    end

    # turn specific error codes to specific exceptions, caller should catch if they care.
    # for 429 they can retry later with some +jitter
    # for anything else, they can choose to retry or give up and have some default behavior.

    def handle_specific_errors(response)
      # rate limited . caller needs to retry with jitter after Retry-After
      if response.code == 429
        # Retry-After: 3600
        error_msg = "Rate limit error."
        retry_after = response.headers['Retry-After']
        if !retry_after.nil?
          error_msg += " Retry after #{retry_after}"
        end

        raise RateLimitError.new(error_msg)
      # 400 errors that caller needs handle or check logs
      elsif response.code == 400
        raise ApiError.new("Fedex API Bad Request")
      elsif response.code == 403
        # maybe project isn't authorized to use this API
        raise ApiError.new("Fedex API Forbidden")
      elsif response.code == 404
        raise ApiError.new("Fedex API Not Found")
      # remote service errors
      elsif response.code == 500
        raise ConnectionError.new("Fedex Service Failure")
      elsif response.code == 503
        raise ConnectionError.new("Fedex Service Unavailable")
      end

    end

  end

end