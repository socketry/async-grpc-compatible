# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "sus/fixtures/openssl"

module TLSContext
	include Sus::Fixtures::OpenSSL::ValidCertificateContext
	
	def url
		"https://127.0.0.1:0"
	end
	
	def certificate
		@tls_certificate ||= super.dup.tap do |certificate|
			extensions = OpenSSL::X509::ExtensionFactory.new
			certificate.add_extension(extensions.create_extension("subjectAltName", "DNS:localhost,IP:127.0.0.1,IP:::1"))
			certificate.sign(certificate_authority_key, OpenSSL::Digest::SHA256.new)
		end
	end
	
	def tls_credentials
		IO::Endpoint::TLS::Configuration.new(
			trust_store: IO::Endpoint::TLS::TrustStore.parse(certificate_authority_certificate.to_pem)
		)
	end
	
	def server_tls_configuration
		IO::Endpoint::TLS::Configuration.new(certificate_chain: [certificate.to_pem], private_key: key.to_pem)
	end
	
	def endpoint_options
		super.merge(tls_configuration: server_tls_configuration)
	end
	
	def make_client_endpoint(bound_endpoint)
		port = bound_endpoint.sockets.first.to_io.local_address.ip_port
		Async::GRPC::Compatible::ClientStub.endpoint_for("https://127.0.0.1:#{port}", tls_credentials)
	end
end
