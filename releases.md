# Releases

## v0.1.0

  - Send `application/grpc` and use shared metadata decoding, including unpadded binary metadata.
  - Map invalid HTTP responses to grpc-ruby errors, preserving the native `ResponseError` and its buffered response as the cause.
  - Support deferred unary operations with execution, cancellation, deadline, status, and response metadata access.
  - Support Ruby authentication callbacks at stub construction and per call, evaluated on each execution with the service's JWT audience and merged into request metadata.
  - Support custom trust roots and mutual TLS through `IO::Endpoint::TLS::Configuration`. Reject opaque native credentials, conflicting target schemes, and authentication callbacks on plaintext channels.
  - Map grpc-ruby's TLS constructor arguments with `Compatible::ChannelCredentials.new(root_certificates, private_key, certificate_chain)`, returning an `IO::Endpoint::TLS::Configuration` with custom roots, client certificate chains, and peer verification enabled.
  - Add `ClientStub.for(service)` and the optional `GapicServiceStub` adapter for generated services and GAPIC clients.
  - Map transport failures to grpc-ruby errors, preserving the original exception as the cause. Connection, DNS, TLS, and HTTP/2 connection failures become `GRPC::Unavailable`, and HTTP/2 stream resets use gRPC's HTTP/2 status mapping.
  - Share connections between stubs for the same target and TLS configuration on each thread, like grpc-core's global subchannel pool. Closing a stub leaves shared clients open; use `SharedChannel.close` to close the current thread's shared clients, or set `grpc.use_local_subchannel_pool` for a stub-owned connection pool.

## v0.0.0

  - Initial implementation of an Async-backed `GRPC::ClientStub` compatible unary client.
