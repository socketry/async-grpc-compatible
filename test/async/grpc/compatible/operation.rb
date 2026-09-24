# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/grpc/compatible/operation"
require "async/queue"
require "sus/fixtures/async"

describe Async::GRPC::Compatible::Operation do
	it "defers execution and yields itself to the call" do
		calls = []
		deadline = Time.now + 60
		operation = subject.new(deadline: deadline) do |call|
			calls << call
			call.metadata = {"request-id" => "123"}
			call.trailing_metadata = {"result" => "complete"}
			:response
		end
		
		expect(calls).to be == []
		expect(operation.deadline).to be == deadline
		expect(operation.status).to be_nil
		expect(operation).not.to be(:cancelled?)
		expect(operation.execute).to be == :response
		expect(calls).to be == [operation]
		expect(operation.metadata).to be == {"request-id" => "123"}
		expect(operation.trailing_metadata).to be == {"result" => "complete"}
		
		operation.cancel
		expect(operation).not.to be(:cancelled?)
		expect{operation.execute}.to raise_exception(RuntimeError, message: be == "Operation has already been executed!")
		expect(calls).to be == [operation]
	end
	
	it "does not execute a call cancelled before it starts" do
		called = false
		operation = subject.new{called = true}
		operation.cancel
		operation.cancel
		
		expect(operation).to be(:cancelled?)
		expect{operation.execute}.to raise_exception(::GRPC::Cancelled)
		expect(called).to be == false
		expect(operation.status.code).to be == ::GRPC::Core::StatusCodes::CANCELLED
		expect{operation.execute}.to raise_exception(RuntimeError, message: be == "Operation has already been executed!")
	end
	
	it "preserves application errors and prevents executing the failed call again" do
		error = IOError.new("Decoder failed!")
		cleaned_up = false
		operation = subject.new do
			raise error
		ensure
			cleaned_up = true
		end
		
		expect{operation.execute}.to raise_exception(IOError).and(be(:equal?, error))
		expect(cleaned_up).to be == true
		expect(operation.status).to be_nil
		operation.cancel
		expect(operation).not.to be(:cancelled?)
		expect{operation.execute}.to raise_exception(RuntimeError, message: be == "Operation has already been executed!")
	end
	
	it "preserves gRPC errors and their status details and metadata" do
		error = ::GRPC::NotFound.new("Missing!", {"reason" => "absent", "details-bin" => "\x00\xff".b})
		operation = subject.new{raise error}
		
		expect{operation.execute}.to raise_exception(::GRPC::NotFound).and(be(:equal?, error))
		expect(operation.status).to be == error.to_status
		operation.cancel
		expect(operation).not.to be(:cancelled?)
		expect(operation.status).to be == error.to_status
	end
	
	it "recognizes cancellation reported by the server" do
		error = ::GRPC::Cancelled.new("Server cancelled!", {"reason" => "shutdown"})
		operation = subject.new{raise error}
		
		expect{operation.execute}.to raise_exception(::GRPC::Cancelled).and(be(:equal?, error))
		expect(operation).to be(:cancelled?)
		expect(operation.status).to be == error.to_status
	end
	
	with "an active call" do
		include Sus::Fixtures::Async::ReactorContext
		
		let(:started) {Async::Queue.new}
		let(:release) {Async::Queue.new}
		let(:events) {[]}
		let(:operation) do
			subject.new do
				started.enqueue(:started)
				release.dequeue
			ensure
				events << :cleaned_up
			end
		end
		
		it "rejects repeated execution without disturbing the active call" do
			execution = Async{operation.execute}
			started.dequeue
			
			expect{operation.execute}.to raise_exception(RuntimeError, message: be == "Operation has already been executed!")
			expect(events).to be == []
			release.enqueue(:response)
			expect(execution.wait).to be == :response
			expect(events).to be == [:cleaned_up]
		end
		
		it "cancels the call and runs cleanup without stopping the caller" do
			execution = Async do
				operation.execute
			rescue ::GRPC::Cancelled => error
				events << :caller_continued
				error
			end
			started.dequeue
			
			operation.cancel
			expect(execution.wait).to be_a(::GRPC::Cancelled)
			expect(events).to be == [:cleaned_up, :caller_continued]
			expect(operation).to be(:cancelled?)
			expect(operation.status.code).to be == ::GRPC::Core::StatusCodes::CANCELLED
			operation.cancel
			expect(events).to be == [:cleaned_up, :caller_continued]
		end
		
		it "rejects execution from another thread and leaves the call cancellable" do
			call = operation
			execution = Async do
				call.execute
			rescue ::GRPC::Cancelled => error
				error
			end
			started.dequeue
			
			error = Thread.new do
				call.execute
			rescue RuntimeError => error
				error
			end.value
			
			expect(error).to be_a(RuntimeError)
			expect(error.message).to be == "Operation has already been executed!"
			expect(events).to be == []
			call.cancel
			expect(execution.wait).to be_a(::GRPC::Cancelled)
			expect(events).to be == [:cleaned_up]
		end
		
		it "rejects cancellation from another thread without cancelling the call" do
			call = operation
			execution = Async{call.execute}
			started.dequeue
			
			error = Thread.new do
				call.cancel
			rescue ThreadError => error
				error
			end.value
			
			expect(error).to be_a(ThreadError)
			expect(error.message).to be == "Cancel the operation from its reactor thread!"
			expect(call).not.to be(:cancelled?)
			expect(events).to be == []
			release.enqueue(:response)
			expect(execution.wait).to be == :response
			expect(events).to be == [:cleaned_up]
		end
		
		it "cleans up the call when its caller is stopped" do
			execution = Async{operation.execute}
			started.dequeue
			
			execution.stop
			expect(events).to be == [:cleaned_up]
			expect{operation.execute}.to raise_exception(RuntimeError, message: be == "Operation has already been executed!")
		end
	end
end
