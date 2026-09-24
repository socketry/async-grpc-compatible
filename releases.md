# Releases

## Unreleased

  - Send `application/grpc` and use shared metadata decoding, including unpadded binary metadata.
  - Map invalid HTTP responses to grpc-ruby errors, preserving the native `ResponseError` and its buffered response as the cause.
  - Support deferred unary operations with execution, cancellation, deadline, status, and response metadata access.
  - Support Ruby authentication callbacks at stub construction and per call, evaluated on each execution with the service's JWT audience and merged into request metadata.
  - Support custom trust roots and mutual TLS through `IO::Endpoint::TLS::Configuration`. Reject opaque native credentials, conflicting target schemes, and authentication callbacks on plaintext channels.
  - Map grpc-ruby's TLS constructor arguments with `Compatible::ChannelCredentials.new(root_certificates, private_key, certificate_chain)`, preserving custom roots and client certificate chains with peer verification enabled.
  - Add `ClientStub.for(service)` and the optional `GapicServiceStub` adapter for generated services and GAPIC clients.

## v0.0.0

  - Initial implementation of an Async-backed `GRPC::ClientStub` compatible unary client.
