# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/grpc/compatible/gapic"

describe Async::GRPC::Compatible::GapicServiceStub do
	let(:service) do
		Class.new do
			include ::GRPC::GenericService
			self.service_name = "compatible.UnitService"
		end
	end
	
	let(:channel) {Async::GRPC::Compatible::Channel.new(client: Object.new)}
	let(:credentials) {->(metadata){metadata.merge("authorization" => "Bearer token")}}
	let(:stub) do
		subject.new(service, endpoint: "example.googleapis.com", credentials: credentials, channel: channel, logger: nil)
	end
	
	it "builds a compatible stub using the shared channel" do
		expect(stub.grpc_stub).to be_a(Async::GRPC::Compatible::ClientStub)
		expect(stub.grpc_stub.channel).to be(:equal?, channel)
		expect(stub.channel_pool).to be_nil
	end
	
	it "leaves the shared channel open when closed" do
		expect(channel).not.to receive(:close)
		
		stub.close
		stub.close
	end
	
	it "closes the client when it owns the channel" do
		owned_stub = subject.new(service, endpoint: "example.googleapis.com", credentials: credentials, logger: nil)
		expect(owned_stub.grpc_stub.channel.endpoint.to_url.to_s).to be == "https://example.googleapis.com/"
		expect(owned_stub.grpc_stub.channel.client).to receive(:close)
		
		owned_stub.close
	end
	
	it "rejects interceptors instead of silently discarding them" do
		expect do
			subject.new(service, endpoint: "example.googleapis.com", credentials: credentials, channel: channel, interceptors: [Object.new], logger: nil)
		end.to raise_exception(NotImplementedError, message: be == "Client interceptors are not yet supported!")
	end
	
	it "rejects native GAPIC channel pooling" do
		pool = ::Gapic::ServiceStub::ChannelPool::Configuration.new
		pool.channel_count = 2
		
		expect do
			subject.new(service, endpoint: "example.googleapis.com", credentials: credentials, channel_pool_config: pool, logger: nil)
		end.to raise_exception(ArgumentError, message: be == "Use a shared Async channel instead of a GAPIC channel pool!")
	end
end
