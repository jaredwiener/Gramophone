class CommandHandler
	def self.handle(commandArray)

		cmd  = commandArray[0]
		if commandArray[1].class.to_s == "Array"
			tid  = commandArray[1].first
		else
			tid = commandArray[1]
		end
		args = commandArray[3..commandArray.length]

		puts "--------------------------"
		puts "COMMAND:        " + cmd.inspect
		puts "TRANSACTION ID: " + tid.inspect
		puts "ARGUMENTS:\n"     + args.inspect
		puts "--------------------------"

		case cmd
			#these are KNOWN COMMANDS.  There may be more that are unsupported. 
		when "connect"
			["_result",tid,nil,{
				"objectEncoding"=>0.0, # in most modern RTMP servers, this would be 3.0.  0.0 lets us keep AMF0 active, instead of AMF3.
									   # the client MUST set object encoding to AMF0, like this:
									   # {netconnection object}.objectEncoding = ObjectEncoding.AMF0; 
				"application"=>nil,
				"level"=>"status",
				"description"=>"Connection succeeded.",
				"code"=>"NetConnection.Connect.Success"
			}]
		when "createStream"
			["_result",tid,nil,1.0]
		when "publish"
			if args[1] == "record"
				["onStatus",tid,nil,{
					"level"=>"status",
					"code"=>"Netstream.Publish.Start",
					"description"=>"",
					"details"=>args[0],
					"clientid"=>1.0
				},"onStatus",tid,nil,{
					"level"=>"status",
					"code"=>"Netstream.Record.Start",
					"description"=>"",
					"details"=>args[0],
					"clientid"=>1.0
				}]
			end
		end
	end
end