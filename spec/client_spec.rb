# frozen_string_literal: true
require "spec_helper"

RSpec.describe FedexRestClient::Client do

  let :credential do
    FedexRestClient::Credential.new("1234567890", "ABCDEFGGFSFASD", "123456")
  end

  let :log_output do
    StringIO.new
  end

  let :logger do
    Logger.new(log_output)
  end

  let :client do
    FedexRestClient::Client.new({
      logger: logger,
      credential: credential
    })
  end

  let :refresh_token_good_response_json do
    '{"access_token": "abc", "expires_in": 1234567}'
  end

  let :from_address do
    {
      company: "blarg co",
      address1: "1234 north south road",
      city: "some town",
      state_abbr: "CA",
      zipcode: "90210",
      country_iso: "US"
    }
  end

  let :to_address do
    {
      address1: "5568 East West Blvd",
      city: "some other town",
      state_abbr: "CA",
      zipcode: "90211",
      country_iso: "US"
    }
  end

  it "should be instantiated instance with accessors" do
    # default vales
    expect(client.fedex_restapi_url).to eq "https://apis-sandbox.fedex.com"
    expect(client.max_retries).to eq 2
    expect(client.retries).to eq 0
  end

  describe "refresh oauth token" do

    it "should refresh oauth token given credentials and store token in credential" do
      expect(credential.oauth_token).to eq nil
      expect(credential.token_expire_at).to eq nil

      stub_request(:post, "https://apis-sandbox.fedex.com/oauth/token").with(
        body: {
          "client_id" => "#{credential.api_key}",
          "client_secret" => "#{credential.api_secret}",
          "grant_type" => "client_credentials"},
        headers: {
          'Accept'=>'*/*',
          'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
          'Content-Type'=>'application/x-www-form-urlencoded',
          'User-Agent'=>'Ruby'
       }).to_return(status: 200, body: refresh_token_good_response_json, headers: {})

      ts = Time.now.to_i
      result = client.refresh_token!
      expect(result).to eq true

      expect(credential.oauth_token).to eq "abc"
      expect(credential.token_expire_at).to eq Time.at(ts + 1234567)
    end


  end

  describe "label construction" do

    it "should construct labels structure with png and ground home" do

      args = {
        from_name: "Test Sender",
        from_address: from_address,
        from_phone: "123-555-2346",
        to_name: "Test Customer",
        to_attn: "RECIVING",
        to_phone: "1235551747",
        to_address: to_address,
        package_weight: 2,
        package_weight_unit: "LB",
        service_type: "GROUND_HOME_DELIVERY",
        label_format: "PNG",
        label_stock_type: "PAPER_LETTER",
        label_rotation: nil,
        return_label: false
      }


      result = client.send(:create_label, args)

      expected = {
        mergeLabelDocOption: "LABELS_ONLY",
        labelResponseOptions: "LABEL",
        requestedShipment: {
          shipper: {
            contact: {
              personName: "Test Sender",
              companyName: "blarg co",
              phoneNumber: "123-555-2346"
            },
            address: {
              streetLines: ["1234 north south road"],
              city: "some town",
              stateOrProvinceCode: "CA",
              postalCode: "90210",
              countryCode: "US"
              }
            },
          recipients: [{
            contact: {
              personName: "Test Customer",
              companyName: "RECIVING",
              phoneNumber: "1235551747"},
              address: {
                streetLines: ["5568 East West Blvd"],
                city: "some other town",
                stateOrProvinceCode: "CA",
                postalCode: "90211",
                countryCode: "US",
                residential: false
              }
            }],
          serviceType: "GROUND_HOME_DELIVERY",
          packagingType: "YOUR_PACKAGING",
          pickupType: "USE_SCHEDULED_PICKUP",
          shippingChargesPayment: {
            paymentType: "SENDER",
          },
          labelSpecification: {
            imageType: "PNG",
            labelStockType: "PAPER_LETTER",
            labelRotation: nil},
          requestedPackageLineItems: [{
            weight: {units: "LB", value: 2}}
          ]},
          accountNumber: {
            value: "123456"
          }
        }
      expect(result).to eq expected

    end

    it "should construct labels structure in ZPLII ground return label" do
      # like a preprinted return label with shipped item
      args = {
        from_name: "Test Sender",
        from_address: from_address,
        from_phone: "123-555-2346",
        to_name: "Test Customer",
        to_attn: "RECIVING",
        to_phone: "1235551747",
        to_address: to_address,
        package_weight: 2,
        package_weight_unit: "LB",
        service_type: "FEDEX_GROUND",
        label_format: "ZPLII",
        label_stock_type: "STOCK_4X6",
        return_label: true,
        bill_third_party: true,
        third_party_account_number: "888123"

      }


      result = client.send(:create_label, args)

      expected = {
        mergeLabelDocOption: "LABELS_ONLY",
        labelResponseOptions: "LABEL",
        requestedShipment: {
          shipper: {
            contact: {
              personName: "Test Sender",
              companyName: "blarg co",
              phoneNumber: "123-555-2346"
            },
          address: {
            streetLines: ["1234 north south road"],
            city: "some town",
            stateOrProvinceCode: "CA",
            postalCode: "90210",
            countryCode: "US"
          }
        },
        recipients: [{
          contact: {
            personName: "Test Customer",
            companyName: "RECIVING",
            phoneNumber: "1235551747"
          },
          address: {
            streetLines: ["5568 East West Blvd"],
            city: "some other town",
            stateOrProvinceCode: "CA",
            postalCode: "90211",
            countryCode: "US",
            residential: false
          }
        }],
        serviceType: "FEDEX_GROUND",
        packagingType: "YOUR_PACKAGING",
        pickupType: "USE_SCHEDULED_PICKUP",
        shippingChargesPayment: {
          paymentType: "THIRD_PARTY",
          payor: {
            responsibleParty: {
              accountNumber: {value: "888123"}
            }
          }
        },
        labelSpecification: {
          imageType: "ZPLII",
          labelStockType: "STOCK_4X6",
          labelRotation: nil
        },
        requestedPackageLineItems: [
          {weight: {units: "LB", value: 2}}
        ],
        shipmentSpecialServices: {
          specialServiceTypes: ["RETURN_SHIPMENT"],
          returnShipmentDetail: { returnType: "PRINT_RETURN_LABEL"}}},
          accountNumber: {value: "123456"}
      }
      puts result
      expect(result).to eq expected

    end

  end

  describe "auto refresh" do

    it "should know if credential needs refresh" do
      # first time, no token of expiration
      expect(client.need_token_refresh?).to eq true

      # have token but no expiration
      credential.oauth_token = "123"
      credential.token_expire_at = nil

      expect(client.need_token_refresh?).to eq true

      # have token but expiration in ast
      credential.oauth_token = "123"
      credential.token_expire_at = Time.now.to_i - 300

      expect(client.need_token_refresh?).to eq true

      # have token, not expired yet
      credential.oauth_token = "123"
      credential.token_expire_at = Time.now.to_i + 300

      expect(client.need_token_refresh?).to eq false
    end

    let :token_expire_response do
      double(:resp, code: 401, body: '{"error": "invalid_request", "error_description": "CXS JWT is expired"}')
    end

    let :token_refresh_response do
      double(:resp, code: 200, body: refresh_token_good_response_json)
    end

    let :good_request_response do
      double(:resp, code: 200, body: '{
        "transactionId": "UUID-1234-5678",
        "output":{
          "transactionShipments": [
            {
              "pieceResponses":
                [
                  {
                    "trackingNumber": "11122233444555" ,
                    "packageDocuments": [
                      {
                        "encodedLabel": "BASE64 ENCODED LABEL HERE"
                      }
                    ]
                  }
                ]
              }
            ]
          }
        }')
    end

    it "should make request to fedex and refresh token if needed" do
      # make requst get expired token
      args = {
        from_name: "Test Sender",
        from_address: from_address,
        from_phone: "123-555-2346",
        to_name: "Test Customer",
        to_attn: "RECIVING",
        to_phone: "1235551747",
        to_address: to_address,
        package_weight: 2,
        package_weight_unit: "LB",
        service_type: "GROUND_HOME_DELIVERY",
        label_format: "PNG",
        label_stock_type: "PAPER_LETTER",
        label_rotation: nil,
        return_label: false
      }

      allow(FedexRestClient::Client).to receive(:post).and_return(
        token_expire_response, # live token expiration
        token_refresh_response, # refresh successful
        good_request_response ) # got new label

      # looks like to be a good token, but it expires during request from fedex side
      credential = client.credential
      credential.oauth_token = "looks go to be good token"
      credential.token_expire_at = Time.now.to_i + 300.to_i

      result = client.fedex_shipping_label(args)

      expect(result).to eq ({image64: "BASE64 ENCODED LABEL HERE", tracking_number: "11122233444555", transaction_id: "UUID-1234-5678"})


    end


  end


end
