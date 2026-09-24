# Async::GRPC::Compatible

grpc-ruby compatible client interfaces backed by `async-grpc` and `async-http`.

The gem is intended for generated clients which currently construct a `GRPC::ClientStub`, but need to make non-blocking calls inside an Async event loop. Connection reuse and HTTP/2 multiplexing remain the responsibility of `async-http`; this gem does not add a second connection pool.

The gem depends on `grpc` for service definitions and error types. TLS configuration comes from `IO::Endpoint`, and requests use Async's connection pool.

## Usage

Select the compatible stub when constructing a generated client:

``` ruby
require "async/grpc/compatible"

stub_class = Async::GRPC::Compatible::ClientStub
stub = stub_class.new("grpc.example.com:443", IO::Endpoint::TLS::Configuration.new)

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
  - Insecure endpoints and TLS using `IO::Endpoint::TLS::Configuration`, including custom trust roots and client certificates, with `Compatible::ChannelCredentials.new` mapping gRPC's positional PEM arguments.
  - Translation of gRPC failures into `GRPC::BadStatus` subclasses.
  - Deferred unary operations using `return_op: true`.
  - Ruby credential updaters supplied through `call_credentials:`, `credentials:`, or a credential object with `updater_proc`.
  - Unary stub generation from `GRPC::GenericService` definitions.

The following are not yet supported:

  - Client, server, or bidirectional streaming.
  - grpc-ruby interceptors.
  - Parent call propagation.
  - Native `GRPC::Core::ChannelCredentials`, `GRPC::Core::CallCredentials`, composed credentials, and native channel overrides. These are rejected because their TLS configuration and authentication callbacks cannot be recovered through Ruby's public API.
  - grpc-ruby channel arguments beyond accepting the compatible constructor parameter.
  - Non-DNS resolvers such as Unix sockets and xDS.

Invalid HTTP responses become `GRPC::BadStatus` subclasses using the HTTP status mapping. The error details describe the invalid HTTP status and content type, and `error.cause` is an `Async::GRPC::ResponseError` whose `response` exposes the HTTP status, headers, and buffered body. Call `error.cause.response.read` to read that body.

Socket and TLS failures can still raise native Ruby exceptions. Translation into grpc-ruby transport errors is tracked separately in [issue #5](https://github.com/socketry/async-grpc-compatible/issues/5).

## Operations and credentials

Pass `return_op: true` to defer a unary call until `operation.execute`. An operation executes once and exposes `deadline`, `metadata`, `trailing_metadata`, `status`, `cancel`, and `cancelled?`. The deadline includes time spent waiting to execute. Cancel an active operation from the same Async reactor; cancelling it closes that call without closing a shared channel. Calling `cancel` after completion has no effect.

Supply `call_credentials:` to the constructor for a default authentication callback, or `credentials:` to `request_response` for a per-call callback. Objects exposing `updater_proc`, such as Google authentication credentials, are also accepted. Callbacks run at execution time on every call, so token refreshes are used.

Each callback receives a fresh authentication context containing `:jwt_aud_uri`, for example `https://grpc.example.com/example.Service`. The audience uses the actual channel's endpoint and RPC service path. Return a hash of authentication headers, or `nil` to add none. Returned headers are merged into a copy of the caller's metadata; per-call credentials run after constructor credentials. The audience context is never sent as a header.

Authentication callbacks require a TLS channel with a known endpoint. A shared `Async::GRPC::Client` supplies its endpoint through its HTTP delegate; for a custom client, supply the endpoint explicitly when constructing `Compatible::Channel.new(endpoint, client: client)`.

``` ruby
stub = Async::GRPC::Compatible::ClientStub.new(
	"grpc.example.com:443",
	IO::Endpoint::TLS::Configuration.new,
	call_credentials: credentials.updater_proc
)
```

Passing an authentication callback as the constructor's second argument creates a default TLS channel with peer and hostname verification. For custom trust roots or mutual TLS, provide the TLS configuration separately:

``` ruby
tls = IO::Endpoint::TLS::Configuration.new(
	trust_store: IO::Endpoint::TLS::TrustStore.load("ca.pem"),
	certificate_chain: IO::Endpoint::TLS::Certificates.parse(File.read("client-chain.pem")),
	private_key: File.read("client-key.pem")
)

stub = Async::GRPC::Compatible::ClientStub.new(
	"grpc.example.com:443", tls,
	call_credentials: credentials.updater_proc
)
```

TLS channels verify peers and hostnames by default, including localhost. An explicit URL must match the selected transport: TLS credentials require `https://`, and `:this_channel_is_insecure` requires `http://`.

### gRPC TLS configuration

`Async::GRPC::Compatible::ChannelCredentials.new` accepts the same three optional positional PEM arguments as `GRPC::Core::ChannelCredentials.new` and returns an `IO::Endpoint::TLS::Configuration` directly:

| gRPC constructor argument | TLS configuration |
| --- | --- |
| Root certificates | `trust_store`, containing only the supplied roots |
| Client private key | `private_key` |
| Client certificate chain | `certificate_chain`, split into individual certificates in the supplied order |

``` ruby
tls = Async::GRPC::Compatible::ChannelCredentials.new(
	File.read("ca.pem"),
	File.read("client-key.pem"),
	File.read("client-chain.pem")
)

stub = Async::GRPC::Compatible::ClientStub.new("grpc.example.com:443", tls)
```

Use `ChannelCredentials.new` for the transport's default trust store, or `ChannelCredentials.new(root_pem)` for custom roots without a client identity. The client key and certificate chain must be supplied together. Peer and hostname verification are always enabled by this mapping. gRPC-specific default-root overrides are not read; supply those roots explicitly.

Pass the returned TLS configuration to `ClientStub` or `GapicServiceStub` at construction. Existing native credential objects cannot be converted through Ruby's public API, so retain the PEM inputs at that boundary. Supply Ruby authentication callbacks separately using `call_credentials:` on `ClientStub`.

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
