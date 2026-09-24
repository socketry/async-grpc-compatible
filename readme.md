# Async::GRPC::Compatible

grpc-ruby compatible client interfaces backed by `async-grpc` and `async-http`.

The gem is intended for generated clients which currently construct a `GRPC::ClientStub`, but need to make non-blocking calls inside an Async event loop. Connection reuse and HTTP/2 multiplexing remain the responsibility of `async-http`; this gem does not add a second connection pool.

The initial release still depends on `grpc` for its public credential and error types, but it does not use the native gRPC channel for requests.

## Usage

Select the compatible stub when constructing a generated client:

``` ruby
require "async/grpc/compatible"

stub_class = Async::GRPC::Compatible::ClientStub
stub = stub_class.new("grpc.example.com:443", GRPC::Core::ChannelCredentials.new)

response = stub.request_response(
	"/example.Service/Get",
	request,
	->(message){message.to_proto},
	Example::Response.method(:decode),
	metadata: {"authorization" => "Bearer token"}
)
```

Applications such as NuevoProtobuf should accept the stub class explicitly rather than replacing the process-wide `GRPC::ClientStub` constant:

``` ruby
NuevoProtobuf::RPC.configure do |config|
	config.client_stub_class = Async::GRPC::Compatible::ClientStub
end
```

That configuration API is illustrative and will require a corresponding NuevoProtobuf change.

## Current Compatibility

The initial implementation supports:

  - The grpc-ruby `GRPC::ClientStub.new` parameter shape.
  - Unary `request_response` calls.
  - Custom marshal and unmarshal callables.
  - Request metadata and deadlines.
  - Insecure and standard TLS endpoints.
  - Translation of gRPC failures into `GRPC::BadStatus` subclasses.
  - Deferred unary operations using `return_op: true`.
  - Ruby credential updaters supplied through `call_credentials:`, `credentials:`, or a credential object with `updater_proc`.
  - Unary stub generation from `GRPC::GenericService` definitions.

The following are not yet supported:

  - Client, server, or bidirectional streaming.
  - grpc-ruby interceptors.
  - Parent call propagation and opaque native `GRPC::Core::CallCredentials` objects.
  - Custom TLS root certificates, client certificates, and native channel overrides.
  - grpc-ruby channel arguments beyond accepting the compatible constructor parameter.
  - Non-DNS resolvers such as Unix sockets and xDS.

Socket and TLS failures can still raise native Ruby exceptions. Translation into grpc-ruby transport errors is tracked separately in [issue #5](https://github.com/socketry/async-grpc-compatible/issues/5).

## Operations and credentials

Pass `return_op: true` to defer a unary call until `operation.execute`. An operation executes once and exposes `deadline`, `metadata`, `trailing_metadata`, `status`, `cancel`, and `cancelled?`. The deadline includes time spent waiting to execute. Cancel an active operation from the same Async reactor; cancelling it closes that call without closing a shared channel. Calling `cancel` after completion has no effect.

Supply `call_credentials:` to the constructor for a default updater, or `credentials:` to `request_response` for a per-call updater. An updater receives a copy of the request metadata and may return updated metadata or mutate it and return `nil`. Objects exposing `updater_proc`, such as Google authentication credentials, are also accepted. The updater runs at execution time on every call, so token refreshes are used. Native composed channel credentials are opaque and cannot provide a Ruby token updater.

``` ruby
stub = Async::GRPC::Compatible::ClientStub.new(
	"grpc.example.com:443",
	GRPC::Core::ChannelCredentials.new,
	call_credentials: credentials.updater_proc
)
```

## GAPIC and generated Google clients

Require the optional adapter after installing your Google client gem (which provides `gapic-common`). `GapicServiceStub` accepts the generated service definition and preserves the original credential updater before GAPIC wraps it in native credentials. Its `call_rpc` path retains GAPIC's retry policies and yields the completed operation to the caller.

``` ruby
require "google/cloud/kms/v1"
require "google/cloud/kms/v1/service_services_pb"
require "async/grpc/compatible/gapic"

credentials = Google::Auth.get_application_default(
	["https://www.googleapis.com/auth/cloud-platform"]
)

Sync do
	service = Async::GRPC::Compatible::GapicServiceStub.new(
		Google::Cloud::Kms::V1::KeyManagementService::Service,
		endpoint: "cloudkms.googleapis.com",
		credentials: credentials
	)
	
	begin
		request = Google::Cloud::Kms::V1::EncryptRequest.new(
			name: "projects/my-project/locations/global/keyRings/my-ring/cryptoKeys/my-key",
			plaintext: "hello"
		)
		response = service.call_rpc(:encrypt, request, options: {timeout: 5}) do |response, operation|
			puts operation.status.code
		end
		puts response.ciphertext.bytesize
	ensure
		service.close
	end
end
```

For an existing Async connection pool, pass `channel:` to the adapter. The caller owns that channel. GAPIC native channel pools are unsupported because Async::HTTP already manages connections.

Generated high-level Google clients construct `Gapic::ServiceStub` inside their constructors. Applications adapting those constructors can use `GapicServiceStub.new(Service, credentials: original_credentials, ...)` at that construction point. The adapter can also be called directly, as above, without replacing global GRPC constants. Keep the original Ruby credentials available at this boundary; credentials already composed into `GRPC::Core::ChannelCredentials` cannot be recovered.

For generated services without GAPIC, use `ClientStub.for(Service)` to construct a stub class with unary RPC methods. Streaming methods raise `NotImplementedError`. This adapter supports the operation methods listed above; native operation controls such as `start_call`, `wait`, and write flags are not implemented.

## Development

Run the test suite:

``` shell
$ bundle exec sus
```

The integration suite includes a unary client fixture generated by
NuevoProtobuf 2.5.4 and exercises it against an in-process Async HTTP/2 server.

## Releases

Please see the [project releases](releases.md) for all releases.

## License

Released under the MIT License.
