# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "io/endpoint/tls/configuration"

module Async
	module GRPC
		module Compatible
			# Maps gRPC channel credentials to transport-neutral TLS configurations.
			module ChannelCredentials
				# Create a TLS configuration using the positional arguments of `GRPC::Core::ChannelCredentials.new`.
				# @parameter root_certificates [String | Nil] The trusted root certificates encoded as a PEM bundle, or nil to use the transport's default trust store.
				# @parameter private_key [String | Nil] The client private key encoded as PEM.
				# @parameter certificate_chain [String | Nil] The client certificate chain encoded as a PEM bundle, with the leaf certificate first.
				# @returns [IO::Endpoint::TLS::Configuration] The transport-neutral TLS configuration.
				# @raises [ArgumentError] If a certificate bundle is empty or the client certificate chain and private key are not supplied together.
				# @raises [TypeError] If certificate or private key material is not a string.
				def self.new(root_certificates = nil, private_key = nil, certificate_chain = nil)
					trust_store = unless root_certificates.nil?
						IO::Endpoint::TLS::TrustStore.parse(root_certificates)
					end
					
					certificates = unless certificate_chain.nil?
						IO::Endpoint::TLS::Certificates.parse(certificate_chain)
					end
					
					IO::Endpoint::TLS::Configuration.new(
						trust_store: trust_store,
						certificate_chain: certificates,
						private_key: private_key,
						verification: :peer
					)
				end
			end
		end
	end
end
