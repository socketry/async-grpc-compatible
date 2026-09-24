# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async"
require "grpc"

module Async
	module GRPC
		module Compatible
			# Represents a deferred unary call. Execute and cancel active calls in the same reactor.
			class Operation
				# Initialize a deferred call.
				# @parameter deadline [Time | Nil] The absolute call deadline.
				# @yields {|operation| ...} Executes the request and records its response.
				def initialize(deadline: nil, &execute)
					@deadline = deadline
					@execute = execute
					@mutex = Thread::Mutex.new
					@executed = false
					@finished = false
					@cancelled = false
					@task = nil
					@thread = nil
					@metadata = nil
					@trailing_metadata = nil
					@status = nil
				end
				
				# @attribute [Time | Nil] The absolute call deadline.
				attr_reader :deadline
				# @attribute [Hash | Nil] The initial response metadata.
				attr_accessor :metadata
				# @attribute [Hash | Nil] The response trailers.
				attr_accessor :trailing_metadata
				# @attribute [Struct::Status | Nil] The completed call status.
				attr_accessor :status
				
				# Execute this operation once, waiting for the response.
				# @returns [Object] The decoded response.
				# @raises [GRPC::BadStatus] If the RPC fails or is cancelled.
				def execute
					@mutex.synchronize do
						raise RuntimeError, "Operation has already been executed" if @executed
						@executed = true
					end
					
					begin
						Sync do |parent|
							task = @mutex.synchronize do
								raise ::GRPC::Cancelled.new("Cancelled") if @cancelled
								@thread = Thread.current
								@task = Async::Task.new(parent, finished: false){@execute.call(self)}
							end
							
							task.run
							result = task.wait
							raise ::GRPC::Cancelled.new("Cancelled") if cancelled?
							result
						ensure
							task&.stop
						end
					rescue ::GRPC::BadStatus => error
						@status = error.to_status
						raise
					ensure
						@mutex.synchronize do
							@finished = true
							@task = nil
						end
						@execute = nil
					end
				end
				
				# Cancel a pending or active operation from its reactor.
				def cancel
					task = @mutex.synchronize do
						return if @finished
						raise ThreadError, "Cancel the operation from its reactor thread" if @task && @thread != Thread.current
						@cancelled = true
						@task
					end
					task&.stop
				end
				
				# Whether cancellation was requested or reported by the server.
				# @returns [Boolean] Whether the operation was cancelled.
				def cancelled?
					@mutex.synchronize{@cancelled || @status&.code == ::GRPC::Core::StatusCodes::CANCELLED}
				end
			end
		end
	end
end
