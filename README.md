# FedexRestClient

Simple Gem that uses the Fedex SHIP API to generate shipping labels. Specifically the Create Shipment endpoint

https://developer.fedex.com/wirc/browser/#operation/Create%20Shipment

Not totally feature complete. Feel free to fork it and implement your own requests.

## Installation

Probably better if you point at this repo or fork of this repo for your specific needs. 

```bash

gem "fedex_rest_client", git: "<this repo>", branch: 'main'

```

## Usage

### Credentials
You will need Fedex developer account. Create account, then create project and pick the right set of APIs to include in your project.

Get these 3 piece of information:
  1. API Key
  2. API Secret Key
  3. account number

This gem will use the API key and API secret to obtain a temporary oauth Bearer token.  This token
is then used to communicate with the fedex RESTful endpoints.  When token is near expiration or already expired, 
client will auto refresh it before new any requsts. 

Once you are ready to go to production, you need to switch your fedex project to production mode.
You will be given new set of credential triplet for production environment. 

### New Label 

__Create a credential object__

```
credential = FedexRestClient::Credential.new("<YOUR API KEY>", "<YOUR API SECRET>", "<YOUR ACCOUNT NUMBER>")

client = FedexRestClient::Client.new({ credential: credential})
```

__Address to and from must be a hash that has these fields__

```
address = {
  company: "Temp Co",
  address1: "1234 North East Drive",
  city: "Some city",
  state_abbr: "CA",
  zipcode: "90210",
  country_iso: "US"
}
```
__Create Label__
```
result = client.fedex_shipping_label({
    from_name: "Test Sender",
    from_address: address,
    from_phone: "1-888-2346",
    to_name: "Test Customer",
    to_attn: "RECIVING",
    to_phone: "1235551747",
    to_address: address,
    package_weight: 2,
    package_weight_unit: "LB",
    service_type: "GROUND_HOME_DELIVERY",
    label_format: "PNG",
    label_stock_type: "PAPER_LETTER",
    label_rotation: nil,
    return_label: false,
    residential_recipient: true
})

==> yields

result = {
  tracking_number: "794819804478", # tracking number
  image64: "iVBORw.....", # label data Base 64 encoded
  transaction_id: "...."  # unique transaction id for each request. 
}
```
__parameters for label creation__

The enum types are well defined in https://developer.fedex.com/wirc/browser/. No need to list all options here. 


| name | type |description |
|---------------------------|---------|-----------------------|
| from_name                 | string | From name (sender)   |   
| from_address              | hash   | From address (sender)  |
| from_phone                | string | From phone (sender) |
| to_name                   | string | To name (receiver) | 
| to_attn                   | string | OPTIONAL: ATTN line on reciving address |
| to_phone                  | string | To phone (reciever) |
| to_address                | hash   | To address (reciever) |
| package_weight            | float  | Approxminum weight of package , default to LB |
| package_weight_unit       | string | weight unit, LB for poinds, KG for kiligrams |
| service_type              | enum/string | type of service requested, see list on Fedex api https://developer.fedex.com/wirc/browser/#/en-us/guides/api-reference?anchor=servicetypes |
| label_format              | enum/string | PNG, ZPLII are few common uses. See fedex doc |
| label_stock_type          | enum/string | size of label. See fedex doc |
| return_label              | boolean | is this label a return service label |
| residential_recipient     | boolean | is the to address a residential address, depend on service requested|
| bill_third_party          | boolean | bill third party with their account number |
| third_party_account_number| string  | 3rd party account number to bill this shipment to |


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/elzoiddy/fedex_rest_client.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
