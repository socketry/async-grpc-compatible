# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "gapic/grpc"
require_relative "client_stub"

module Async
	module GRPC
		module Compatible
			# Represents a GAPIC service stub that preserves Ruby credential updaters.
			class GapicServiceStub < ::Gapic::ServiceStub
				# Initialize a GAPIC adapter for a generated service definition.
				# @parameter service [Class] The generated GRPC::GenericService definition.
				# @parameter channel [Channel | Nil] An optional shared Async channel.
				# @parameter options [Hash] GAPIC service options, including credentials and endpoint.
				def initialize(service, channel: nil, **options)
					@service_name = service.service_name
					@async_channel = channel
					super(ClientStub.for(service), **options)
				end
				
				# Construct the Async stub before GAPIC converts credentials into opaque native objects.
				# @parameter grpc_stub_class [Class] The compatible stub class.
				# @parameter endpoint [String] The service endpoint.
				# @parameter credentials [Object] The original GAPIC credentials.
				# @parameter channel_args [Hash | Nil] Channel arguments.
				# @parameter interceptors [Array | Nil] Client interceptors.
				def create_grpc_stub(grpc_stub_class, endpoint:, credentials:, channel_args: nil, interceptors: nil)
					@grpc_stub = grpc_stub_class.new(endpoint, credentials,
						channel_override: @async_channel,
						channel_args: channel_args || {},
						interceptors: interceptors || [])
				end
				
				# Async::HTTP owns connection pooling; native GAPIC channel pools are unsupported.
				def create_channel_pool(...)
					raise ArgumentError, "Use a shared Async channel instead of a GAPIC channel pool!"
				end
				
				# Close the underlying stub's owned connection pool, leaving shared clients open.
				def close
					@grpc_stub&.close
				end
				
				# Supply a service identity for the anonymous generated stub class.
				# @private
				def setup_logging(system_name: nil, service: nil, **options)
					super(system_name: "async-grpc-compatible", service: @service_name, **options)
				end
			end
		end
	end
end
