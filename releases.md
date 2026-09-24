# Releases

## Unreleased

  - Send `application/grpc` and use shared metadata decoding, including unpadded binary metadata.
  - Map invalid HTTP responses to grpc-ruby errors, preserving the native `ResponseError` and its buffered response as the cause.
  - Support deferred unary operations with execution, cancellation, deadline, status, and response metadata access.
  - Support Ruby credential updaters at stub construction and per call, evaluated on each execution.
  - Add `ClientStub.for(service)` and the optional `GapicServiceStub` adapter for generated services and GAPIC clients.

## v0.0.0

  - Initial implementation of an Async-backed `GRPC::ClientStub` compatible unary client.
