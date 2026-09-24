# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/grpc/compatible/channel_credentials"
require "sus/fixtures/openssl"

describe Async::GRPC::Compatible::ChannelCredentials do
	include Sus::Fixtures::OpenSSL::ValidCertificateContext
	
	let(:roots) {certificate_authority_certificate.to_pem}
	let(:chain) {certificate.to_pem + roots}
	let(:private_key) {key.to_pem}
	
	it "uses the default trust store with peer verification when no roots are supplied" do
		configuration = subject.new
		
		expect(configuration).to be_a(IO::Endpoint::TLS::Configuration)
		expect(configuration.trust_store).to be_nil
		expect(configuration.certificate_chain).to be_nil
		expect(configuration.private_key).to be_nil
		expect(configuration.verification).to be == :peer
	end
	
	it "maps gRPC positional arguments and preserves certificate bundle ordering" do
		configuration = subject.new(roots + certificate.to_pem, private_key, chain)
		
		expect(configuration.trust_store.certificates).to be == [roots.strip, certificate.to_pem.strip]
		expect(configuration.trust_store.system_certificates?).to be == false
		expect(configuration.certificate_chain).to be == [certificate.to_pem.strip, roots.strip]
		expect(configuration.private_key).to be == private_key
		expect(configuration.verification).to be == :peer
	end
	
	it "allows a client identity with the default trust store" do
		configuration = subject.new(nil, private_key, chain)
		
		expect(configuration.trust_store).to be_nil
		expect(configuration.certificate_chain).to be == [certificate.to_pem.strip, roots.strip]
		expect(configuration.private_key).to be == private_key
		expect(configuration.verification).to be == :peer
	end
	
	it "requires both the client certificate chain and private key" do
		expect do
			subject.new(roots, private_key)
		end.to raise_exception(ArgumentError, message: be =~ /certificate chain and private key/)
		
		expect do
			subject.new(roots, nil, chain)
		end.to raise_exception(ArgumentError, message: be =~ /certificate chain and private key/)
	end
	
	it "rejects empty or invalid certificate bundles" do
		["", "not a certificate"].each do |bundle|
			expect{subject.new(bundle)}.to raise_exception(ArgumentError, message: be =~ /does not contain any certificates/)
			expect{subject.new(roots, private_key, bundle)}.to raise_exception(ArgumentError, message: be =~ /does not contain any certificates/)
		end
	end
	
	it "rejects non-string TLS material" do
		expect{subject.new(false)}.to raise_exception(TypeError)
		expect{subject.new(roots, false, chain)}.to raise_exception(TypeError)
		expect{subject.new(roots, private_key, false)}.to raise_exception(TypeError)
	end
end
