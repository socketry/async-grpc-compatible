# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

source "https://rubygems.org"

gemspec

local_async_grpc_path = File.expand_path("../async-grpc", __dir__)

if File.directory?(local_async_grpc_path)
	gem "async-grpc", path: local_async_grpc_path
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
	gem "googleauth"
	
	gem "covered"
	gem "sus"
	
	gem "rubocop"
	gem "rubocop-md"
	gem "rubocop-socketry"
	
	gem "sus-fixtures-async-http"
	gem "sus-fixtures-openssl"
	
	gem "bake-test"
	gem "bake-test-external"
end
