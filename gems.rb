# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

source "https://rubygems.org"

gemspec

# Use the shared fixes while their releases are pending:
gem "protocol-grpc", git: "https://github.com/socketry/protocol-grpc.git", ref: "4a35b7cdb9d88e64794d2cf05ba72d9de1140aa9"

local_async_grpc_path = File.expand_path("../async-grpc", __dir__)

if File.directory?(local_async_grpc_path)
	gem "async-grpc", path: local_async_grpc_path
else
	gem "async-grpc", git: "https://github.com/socketry/async-grpc.git", ref: "f1f7ff58487e3f79dffd1481ce1665796c6b69db"
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
