# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

source "https://rubygems.org"

gemspec

# Use the shared fixes while their releases are pending:
gem "protocol-grpc", git: "https://github.com/socketry/protocol-grpc.git", ref: "cb474e449da5864a91206a680c2543e84619ea89"

local_async_grpc_path = File.expand_path("../async-grpc", __dir__)

if File.directory?(local_async_grpc_path)
	gem "async-grpc", path: local_async_grpc_path
else
	gem "async-grpc", git: "https://github.com/socketry/async-grpc.git", ref: "24a57196c8f74d7f12d9fb9cd43132b5ea8930c1"
end

group :maintenance, optional: true do
	gem "bake-gem"
	gem "bake-modernize"
	gem "bake-releases"
	
	gem "agent-context"
	
	gem "decode"
	
	gem "utopia-project"
end

group :test do
	gem "gapic-common"
	
	gem "covered"
	gem "sus"
	
	gem "rubocop"
	gem "rubocop-md"
	gem "rubocop-socketry"
	
	gem "sus-fixtures-async-http"
	
	gem "bake-test"
	gem "bake-test-external"
end
