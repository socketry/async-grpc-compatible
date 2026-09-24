# frozen_string_literal: true

require_relative "lib/async/grpc/compatible/version"

Gem::Specification.new do |specification|
	specification.name = "async-grpc-compatible"
	specification.version = Async::GRPC::Compatible::VERSION
	
	specification.summary = "grpc-ruby compatible client interfaces using Async::GRPC."
	specification.authors = ["Samuel Williams"]
	specification.license = "MIT"
	
	specification.homepage = "https://github.com/socketry/async-grpc-compatible"
	
	specification.metadata = {
		"documentation_uri" => "https://socketry.github.io/async-grpc-compatible/",
		"source_code_uri" => "https://github.com/socketry/async-grpc-compatible.git",
	}
	
	specification.files = Dir.glob(["{context,lib}/**/*", "*.md"], File::FNM_DOTMATCH, base: __dir__)
	
	specification.required_ruby_version = ">= 3.3"
	
	specification.add_dependency "async-grpc", "~> 0.10"
	specification.add_dependency "async-http", "~> 0.100"
	specification.add_dependency "grpc"
	specification.add_dependency "io-endpoint", "~> 0.19"
	specification.add_dependency "protocol-grpc", "~> 0.17"
end
