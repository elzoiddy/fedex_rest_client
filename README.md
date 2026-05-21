# FedexRestClient

Simple Gem that uses the Fedex SHIP RESTful API to generate shipping labels. 
Not totally feature complete. 

## Installation

Install the gem and add to the application's Gemfile by executing:
Maybe better if you point at this repo or fork of this repo for your specific needs. 

```bash

bundle add fedex_rest_client, git: "<this repo>", :branch => 'master'

```

## Usage

### Credentials
You will need Fedex developer account. Create account, create project

Get these 3 piece of credentials
  a. API Key
  b. API Secret
  c. account number. 

This gem will use the API key and API secret to obtain a temporary oauth barer token.  That token
is then use to communicate with the fedex restful endpoints.  When token is near expiration or already expired, 
client will auto refresh it before new requst are made. 

TODO: more details usage. 


## Development


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/elzoiddy/fedex_rest_client.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
