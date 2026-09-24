# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/grpc"
require "async/http/endpoint"
require "async/http/protocol/http2"
require "base64"
require "openssl"
require "grpc"
require "io/endpoint/tls/configuration"
require "protocol/grpc/body/readable"
require "protocol/grpc/body/writable"
require "protocol/grpc/metadata"
require_relative "channel_credentials"
require_relative "operation"

::Thread.attr_accessor :async_grpc_compatible_shared_clients

module Async
	module GRPC
		module Compatible
			# Represents a reusable Async gRPC channel.
			class Channel
				# Initialize a channel for the given endpoint.
				# @parameter endpoint [Async::HTTP::Endpoint | Nil] The remote HTTP/2 endpoint, inferred from a supplied Async client when possible.
				# @parameter client [Async::GRPC::Client | Nil] An existing client to use.
				def initialize(endpoint = nil, client: nil)
					@endpoint = endpoint
					if @endpoint.nil? && client.is_a?(Async::GRPC::Client) && client.delegate.respond_to?(:endpoint)
						@endpoint = client.delegate.endpoint
					end
					@client = client || Async::GRPC::Client.open(endpoint)
					@owned = client.nil?
				end
				
				# @attribute [Async::HTTP::Endpoint | Nil] The remote endpoint.
				attr_reader :endpoint
				
				# @attribute [Async::GRPC::Client] The shared Async gRPC client.
				attr_reader :client
				
				# Close the underlying client when it is owned by this channel.
				def close
					@client.close if @owned
				end
			end
			
			# Represents a channel whose client is shared with other shared channels for the same URL and TLS configuration on the same thread.
			#
			# Each thread has its own client because an Async connection pool belongs to a single reactor.
			class SharedChannel < Channel
				# @returns [Hash] The current thread's shared clients, keyed by URL and TLS configuration.
				def self.clients
					::Thread.current.async_grpc_compatible_shared_clients ||= {}
				end
				
				# Close the current thread's shared clients. Shared channels open new clients on their next call.
				def self.close
					# Detach the clients before closing them, since closing may yield to a call which opens a new client:
					clients = ::Thread.current.async_grpc_compatible_shared_clients
					::Thread.current.async_grpc_compatible_shared_clients = nil
					
					clients&.each_value(&:close)
				end
				
				# Initialize a shared channel for the given URL and TLS configuration.
				#
				# The channel freezes a copy of the TLS configuration, so later changes by the caller do not affect shared clients.
				#
				# @parameter url [String] The remote `http` or `https` URL.
				# @parameter tls_configuration [IO::Endpoint::TLS::Configuration | Nil] The TLS configuration for an `https` URL.
				def initialize(url, tls_configuration = nil)
					tls_configuration = tls_configuration&.dup&.freeze
					@endpoint = Async::HTTP::Endpoint.parse(url, protocol: Async::HTTP::Protocol::HTTP2, tls_configuration: tls_configuration)
					@key = ["#{@endpoint.scheme}://#{@endpoint.authority}", tls_configuration]
				end
				
				# @attribute [Async::GRPC::Client] The current thread's client for this endpoint.
				def client
					self.class.clients[@key] ||= Async::GRPC::Client.open(@endpoint)
				end
				
				# Leave the shared client open for other channels.
				def close
				end
			end
			
			# Represents a subset of `GRPC::ClientStub` backed by {Async::GRPC::Client}.
			class ClientStub
				INSECURE_CREDENTIALS = :this_channel_is_insecure
				LOCAL_SUBCHANNEL_POOL = "grpc.use_local_subchannel_pool"
				DEFAULT_TIMEOUT = nil
				
				# Transport failures which end a call without a gRPC status. grpc-ruby reports these as `UNAVAILABLE`.
				TRANSPORT_ERRORS = [
					::Protocol::HTTP::RefusedError,
					::Protocol::HTTP2::Error,
					::Protocol::HPACK::Error,
					IOError,
					SocketError,
					SystemCallError,
					OpenSSL::SSL::SSLError,
				].freeze
				
				# The gRPC status for each HTTP/2 stream reset code, from gRPC's HTTP/2 status mapping. Other codes map to `INTERNAL`.
				STREAM_RESET_STATUSES = {
					::Protocol::HTTP2::Error::REFUSED_STREAM => ::GRPC::Core::StatusCodes::UNAVAILABLE,
					::Protocol::HTTP2::Error::CANCEL => ::GRPC::Core::StatusCodes::CANCELLED,
					::Protocol::HTTP2::Error::ENHANCE_YOUR_CALM => ::GRPC::Core::StatusCodes::RESOURCE_EXHAUSTED,
					::Protocol::HTTP2::Error::INADEQUATE_SECURITY => ::GRPC::Core::StatusCodes::PERMISSION_DENIED,
				}.freeze
				
				# Build a compatible stub class for a generated GRPC::GenericService.
				# @parameter service [Class] The generated service definition.
				# @returns [Class] A client stub with methods for the service's unary RPCs.
				def self.for(service)
					Class.new(self) do
						service.rpc_descs.each do |name, description|
							method_name = ::GRPC::GenericService.underscore(name.to_s)
							path = "/#{service.service_name}/#{name}"
							marshal = description.marshal_proc
							unmarshal = description.unmarshal_proc(:output)
							define_method(method_name) do |request, **options|
								raise NotImplementedError, "Streaming RPCs are not yet supported!" unless description.request_response?
								request_response(path, request, marshal, unmarshal, **options)
							end
						end
					end
				end
				
				# Construct a compatible channel.
				#
				# Without an override, the channel shares connections with other stubs for the same target and TLS configuration on the current thread. Set the `grpc.use_local_subchannel_pool` channel argument to a non-zero value to use a client owned by this channel instead.
				#
				# @parameter channel_override [Channel, Async::GRPC::Client | Nil] An existing compatible channel or client.
				# @parameter host [String] The gRPC target.
				# @parameter credentials [IO::Endpoint::TLS::Configuration, Symbol] The channel TLS configuration or insecure marker.
				# @parameter channel_arguments [Hash] gRPC channel arguments.
				# @returns [Channel] The compatible channel.
				def self.setup_channel(channel_override, host, credentials, channel_arguments = {})
					case channel_override
					when Channel
						return channel_override
					when Async::GRPC::Client
						return Channel.new(client: channel_override)
					when nil
						# Continue constructing the channel:
					else
						raise TypeError, "Channel override must be an Async::GRPC::Compatible::Channel or Async::GRPC::Client!"
					end
					
					# grpc-ruby accepts string and symbol keys. Only fall back on nil, so an explicit false is preserved:
					local_pool = channel_arguments[LOCAL_SUBCHANNEL_POOL]
					local_pool = channel_arguments[LOCAL_SUBCHANNEL_POOL.to_sym] if local_pool.nil?
					
					# gRPC uses integer boolean flags (0/1). Ruby treats 0 as truthy, so check it explicitly:
					if local_pool && local_pool != 0
						Channel.new(endpoint_for(host, credentials, channel_arguments))
					else
						SharedChannel.new(url_for(host, credentials), tls_configuration_for(credentials))
					end
				end
				
				# Construct an HTTP/2 endpoint for a gRPC target.
				#
				# Channels with a local subchannel pool use this endpoint. Shared channels are identified by their URL and TLS configuration, so they are constructed from {url_for} and {tls_configuration_for} instead.
				#
				# @parameter host [String] The gRPC target.
				# @parameter credentials [IO::Endpoint::TLS::Configuration, Symbol] The channel TLS configuration or insecure marker.
				# @parameter channel_arguments [Hash] gRPC channel arguments.
				# @returns [Async::HTTP::Endpoint] The HTTP/2 endpoint.
				def self.endpoint_for(host, credentials, channel_arguments = {})
					Async::HTTP::Endpoint.parse(url_for(host, credentials), protocol: Async::HTTP::Protocol::HTTP2, tls_configuration: tls_configuration_for(credentials))
				end
				
				# Construct the URL for a gRPC target.
				# @parameter host [String] The gRPC target.
				# @parameter credentials [IO::Endpoint::TLS::Configuration, Symbol] The channel TLS configuration or insecure marker.
				# @returns [String] The `http` or `https` URL.
				def self.url_for(host, credentials)
					raise TypeError, "Host must be a String!" unless host.is_a?(String)
					
					scheme = scheme_for(credentials)
					target = normalize_target(host)
					
					if target.match?(/\Ahttps?:\/\//)
						url = target
					else
						url = "#{scheme}://#{target}"
					end
					
					raise ArgumentError, "Target scheme must match the channel credentials!" unless url.start_with?("#{scheme}://")
					
					return url
				end
				
				# Construct the TLS configuration for the given credentials.
				# @parameter credentials [IO::Endpoint::TLS::Configuration, Symbol] The channel TLS configuration or insecure marker.
				# @returns [IO::Endpoint::TLS::Configuration | Nil] The TLS configuration, or `nil` for insecure credentials.
				def self.tls_configuration_for(credentials)
					return nil if scheme_for(credentials) == "http"
					
					IO::Endpoint::TLS::Configuration.new(
						trust_store: credentials.trust_store,
						certificate_chain: credentials.certificate_chain,
						private_key: credentials.private_key,
						verification: credentials.verification || :peer
					)
				end
				
				# Determine the URL scheme for the given credentials.
				# @parameter credentials [IO::Endpoint::TLS::Configuration, Symbol] The channel TLS configuration or insecure marker.
				# @returns [String] Either `"http"` or `"https"`.
				def self.scheme_for(credentials)
					return "http" if credentials == INSECURE_CREDENTIALS
					
					if credentials.is_a?(IO::Endpoint::TLS::Configuration)
						return "https"
					end
					
					raise TypeError, "Credentials must be IO::Endpoint::TLS::Configuration or :this_channel_is_insecure; native gRPC credentials are unsupported!"
				end
				
				# Normalize a grpc-ruby target into an HTTP authority.
				# @parameter host [String] The gRPC target.
				# @returns [String] The normalized target.
				def self.normalize_target(host)
					if host.start_with?("dns:///")
						host.delete_prefix("dns:///")
					elsif host.start_with?("dns://")
						host.delete_prefix("dns://").delete_prefix("/")
					elsif host.match?(/\A(?:unix|unix-abstract|ipv4|ipv6|xds|passthrough):/i)
						raise ArgumentError, "Unsupported gRPC target: #{host.inspect}!"
					else
						host
					end
				end
				
				# Create a compatible client stub.
				# @parameter host [String] The gRPC target.
				# @parameter credentials [IO::Endpoint::TLS::Configuration, Symbol, Proc, Object, Nil] The channel TLS configuration, insecure marker, or Ruby authentication callback. Callbacks use a default verified TLS channel. Nil requires a channel override.
				# @parameter channel_override [Channel, Async::GRPC::Client | Nil] An existing compatible channel or client.
				# @parameter timeout [Numeric | Nil] The default relative timeout in seconds.
				# @parameter propagate_mask [Integer | Nil] Reserved for grpc-ruby compatibility.
				# @parameter channel_args [Hash] gRPC channel arguments.
				# @parameter call_credentials [Proc | Object | Nil] An authentication callback or an object with updater_proc.
				# @parameter interceptors [Array] grpc-ruby client interceptors, which are not yet supported.
				def initialize(host, credentials,
					channel_override: nil,
					timeout: nil,
					propagate_mask: nil,
					channel_args: {},
					interceptors: [],
					call_credentials: nil)
					raise NotImplementedError, "Client interceptors are not yet supported!" unless interceptors.empty?
					
					if credentials.respond_to?(:updater_proc) || credentials.respond_to?(:call)
						raise ArgumentError, "Supply call credentials only once!" if call_credentials
						call_credentials = credentials
						credentials = IO::Endpoint::TLS::Configuration.new(verification: :peer)
					end
					self.class.scheme_for(credentials) unless credentials.nil? && channel_override
					@call_credentials = call_credentials
					channel_arguments = channel_args.dup
					@channel = self.class.setup_channel(channel_override, host, credentials, channel_arguments)
					@owned_channel = channel_override.nil?
					@timeout = timeout
					@propagate_mask = propagate_mask
				end
				
				# @attribute [Channel] The compatible channel.
				attr_reader :channel
				attr_writer :propagate_mask
				
				# Send a unary request and return its response.
				# @parameter method [String] The fully qualified RPC path.
				# @parameter request [Object] The request object.
				# @parameter marshal [Proc] A callable which encodes the request.
				# @parameter unmarshal [Proc] A callable which decodes the response.
				# @parameter deadline [Time | Nil] The absolute call deadline.
				# @parameter return_op [Boolean] Whether to return an operation object.
				# @parameter parent [Object | Nil] A parent server call.
				# @parameter credentials [Object | Nil] Per-call credentials.
				# @parameter metadata [Hash] Request metadata.
				# @returns [Object] The decoded response.
				# @raises [GRPC::BadStatus] If the call fails.
				def request_response(method, request, marshal, unmarshal,
					deadline: nil,
					return_op: false,
					parent: nil,
					credentials: nil,
					metadata: {})
					raise NotImplementedError, "Parent call propagation is not yet supported!" if parent
					
					timeout = relative_timeout(deadline)
					call_deadline = timeout && Time.now + timeout
					operation = Operation.new(deadline: call_deadline) do |operation|
						execute_request_response(method, request, marshal, unmarshal, metadata, credentials, operation)
					end
					return operation if return_op
					
					operation.execute
				end
				
				# Close a channel created by this stub. Shared clients remain open for other stubs.
				def close
					@channel.close if @owned_channel
				end
				
			private
				
				def execute_request_response(method, request, marshal, unmarshal, metadata, credentials, operation)
					timeout = operation.deadline && operation.deadline - Time.now
					raise_deadline_exceeded if timeout && timeout <= 0
					
					Sync do |task|
						if timeout
							task.with_timeout(timeout, Async::GRPC::DeadlineExceededError) do
								metadata = update_metadata(metadata, credentials, method)
								invoke_request_response(method, request, marshal, unmarshal, metadata, timeout, operation)
							end
						else
							metadata = update_metadata(metadata, credentials, method)
							invoke_request_response(method, request, marshal, unmarshal, metadata, nil, operation)
						end
					end
				rescue Async::GRPC::DeadlineExceededError
					raise_deadline_exceeded
				rescue Async::GRPC::ResponseError => error
					status = Protocol::GRPC::Status.for_http_status(error.response.status)
					raise_bad_status(status, error.message, {}, cause: error)
				rescue Protocol::GRPC::Error => error
					raise_bad_status(error.status_code, error.cause&.message || error.message, error.metadata, cause: error)
				end
				
				def update_metadata(metadata, credentials, method)
					metadata = normalize_metadata(metadata)
					[@call_credentials, credentials].compact.each do |updater|
						updater = updater.updater_proc if updater.respond_to?(:updater_proc)
						raise TypeError, "Call credentials must be callable or expose updater_proc!" unless updater.respond_to?(:call)
						
						endpoint = @channel.endpoint
						raise ArgumentError, "Call credentials require a secure channel with a known endpoint!" unless endpoint && endpoint.scheme == "https"
						service = normalize_method(method).rpartition("/").first
						context = {jwt_aud_uri: "https://#{endpoint.authority}#{service}"}
						attributes = updater.call(context)
						next if attributes.nil?
						raise TypeError, "Call credentials must return a Hash or nil!" unless attributes.is_a?(Hash)
						
						# Google updaters can return the context along with authentication headers.
						attributes.each do |key, value|
							key = key.to_s
							metadata[key] = value unless key == "jwt_aud_uri"
						end
					end
					metadata
				end
				
				def invoke_request_response(method, request, marshal, unmarshal, metadata, timeout, operation)
					body = Protocol::GRPC::Body::Writable.new
					payload = marshal.call(request)
					raise TypeError, "Marshal must return a String!" unless payload.is_a?(String)
					
					body.write(payload)
					body.close_write
					
					timeout = operation.deadline && operation.deadline - Time.now
					raise_deadline_exceeded if timeout && timeout <= 0
					
					headers = build_headers(
						metadata: normalize_metadata(metadata),
						timeout: timeout,
						content_type: "application/grpc"
					)
					request = Protocol::HTTP::Request["POST", normalize_method(method), headers, body]
					payload = perform_request(request, operation)
					
					payload ? unmarshal.call(payload) : nil
				end
				
				# Send the request and read its response payload. Application callbacks run outside this method, so their errors are not treated as transport failures.
				def perform_request(request, operation)
					response = @channel.client.call(request)
					
					begin
						operation.metadata = extract_metadata(Protocol::HTTP::Headers.new(response.headers.header.to_a, policy: Protocol::GRPC::HEADER_POLICY))
						response_encoding = response.headers["grpc-encoding"]
						response_body = Protocol::GRPC::Body::Readable.wrap(response, encoding: response_encoding)
						payload = response_body&.read
						response_body&.finish
						
						operation.trailing_metadata = extract_metadata(Protocol::HTTP::Headers.new(response.headers.trailer.to_a, policy: Protocol::GRPC::HEADER_POLICY))
						operation.status = ::Struct::Status.new(
							Protocol::GRPC::Metadata.extract_status(response.headers),
							Protocol::GRPC::Metadata.extract_message(response.headers),
							operation.trailing_metadata
						)
						check_status!(response)
						
						payload
					ensure
						response.close
					end
				rescue ::Protocol::HTTP2::StreamError => error
					status = STREAM_RESET_STATUSES.fetch(error.code, ::GRPC::Core::StatusCodes::INTERNAL)
					raise_bad_status(status, error.message, {}, cause: error)
				rescue ::Protocol::HTTP::RemoteError => error
					# The peer reset the stream with `INTERNAL_ERROR`:
					raise_bad_status(::GRPC::Core::StatusCodes::INTERNAL, error.message, {}, cause: error)
				rescue *TRANSPORT_ERRORS => error
					raise_bad_status(::GRPC::Core::StatusCodes::UNAVAILABLE, error.message, {}, cause: error)
				end
				
				def check_status!(response)
					status = Protocol::GRPC::Metadata.extract_status(response.headers)
					return if status == Protocol::GRPC::Status::OK
					
					details = Protocol::GRPC::Metadata.extract_message(response.headers)
					metadata = extract_metadata(response.headers)
					raise_bad_status(status, details, metadata)
				end
				
				def build_headers(metadata:, timeout:, content_type:)
					headers = Protocol::HTTP::Headers.new(policy: Protocol::GRPC::HEADER_POLICY)
					headers["content-type"] = content_type
					headers["te"] = "trailers"
					headers["grpc-timeout"] = timeout if timeout
					
					metadata.each do |key, value|
						headers[key] = if key.end_with?("-bin")
							Base64.strict_encode64(value)
						else
							value.to_s
						end
					end
					
					return headers
				end
				
				def extract_metadata(headers)
					Protocol::GRPC::Metadata.extract(headers)
				end
				
				def normalize_method(method)
					method = method.to_s
					method.start_with?("/") ? method : "/#{method}"
				end
				
				def normalize_metadata(metadata)
					metadata.to_h.each_with_object({}) do |(key, value), normalized|
						normalized[key.to_s] = value
					end
				end
				
				def relative_timeout(deadline)
					return relative_default_timeout if deadline.nil?
					
					if defined?(::GRPC::Core::TimeConsts::INFINITE_FUTURE) && deadline == ::GRPC::Core::TimeConsts::INFINITE_FUTURE
						return nil
					end
					
					if defined?(::GRPC::Core::TimeConsts::ZERO) && deadline == ::GRPC::Core::TimeConsts::ZERO
						return 0
					end
					
					if deadline.respond_to?(:to_time)
						deadline.to_time - Time.now
					elsif deadline.is_a?(Numeric)
						deadline
					else
						raise TypeError, "Deadline must be a Time or Numeric value!"
					end
				end
				
				def relative_default_timeout
					return nil if @timeout.nil? || @timeout < 0
					
					@timeout
				end
				
				def raise_deadline_exceeded
					raise_bad_status(::GRPC::Core::StatusCodes::DEADLINE_EXCEEDED, "Deadline exceeded!", {})
				end
				
				def raise_bad_status(status, details, metadata, cause: nil)
					error = ::GRPC::BadStatus.new_status_exception(status, details || "Unknown cause!", metadata)
					raise error, cause: cause
				end
			end
		end
	end
end
