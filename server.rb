##################################################
#                                                #
#                   GRAMOPHONE                   #
# 											     #
#  An RTMPT audio recording server for Sinatra   #
#                                                #
##################################################
                                

require 'sinatra'
require 'sinatra/activerecord' # awesome - https://github.com/janko-m/sinatra-activerecord
load 'rubyamfparser.rb'
load 'commandhandler.rb'
load 'flvwriter.rb'

# just for development
require "sinatra/base"
require "sinatra/reloader"

set :database, {adapter: "sqlite3", database: "db/rtmpt_sessions.db"}

class Gramophone < Sinatra::Base

	#just for development
	configure :development do
  	  register Sinatra::Reloader
    end
    #/development

	register Sinatra::ActiveRecordExtension

	# constants
	RTMP_SET_PACKET_SIZE  = 0x01 # Set Packet Size Message.
	RTMP_PING_MESSAGE     = 0x04 # Ping Message.
	RTMP_SERVER_BANDWIDTH = 0x05 # Server Bandwidth
	RTMP_CLIENT_BANDWIDTH = 0x06 # Client Bandwidth.
	RTMP_AUDIO_PACKET     = 0x08 # Audio Packet.
	RTMP_VIDEO_PACKET     = 0x09 # Video Packet.
	RTMP_AMF3_COMMAND     = 0x11 # An AMF3 type command.
	RTMP_INVOKE           = 0x12 # Invoke (onMetaData info is sent as such).
	RTMP_AMF0_COMMAND     = 0x14 # An AMF0 type command.

	MEDIA_STORAGE_PATH	  = "media"

	# let's get somet things straight here -- we're changing the headers
	# to be consistent with what we're looking for

	configure do
		disable :protection
	end

	before do
		content_type 'application/x-fcs'
		headers \
			"Connection" => "keep-alive",
			"Cache-Control" => "no-cache",
			"Server" => "Ruby RTMPT Server/0.0.1"
	end

	def increment 
		if Session.exists?params[:session].to_i
			session = Session.find(params[:session].to_i)
			if params[:i].to_i == session.request+1
				session.request += 1
				session.save!
			else
				halt 410 #gone
			end
		else
			halt 404
		end
	end

	def addHeader(body, streamID, time, first=true, isAMF=true)
		if first
			# for now, lets just give everything a full header

			if streamID < 64 # this means the first 2 bits are 0
				header = numberToChars(streamID) 			      + # first byte
						 numberToChars((Time.now - time).to_i,3)  + # timestamp delta
						 numberToChars(body.length,3)			  + # packet length
						 20.chr 								  + # this should probable change == 20 = x14, or AMF0 flag
						 bytePad("\x00",4)							# again, hardcoded - message stream as 0
			else
				raise "Stream ID, which is currently #{streamID.to_s}, cannot be greater than 63."
			end

		else
			# this can be a one byte header, just include the streamID
			# b11000000 = xC0
			header = ("11" + streamID.unpack("B*")).pack("B*")
		end

		# add in one-byte headers every 128 bytes in body
		x=128
		while x < body.length
			body.insert(x,(0b11000000 + streamID).chr)
			x+=128
		end

		header + body
	end

	def readHeader(raw)
		parsed = {}

		# basicHeader = numToOctet(raw[0].unpack("H*")[0].to_i)
		basicHeader = raw[0].unpack("B8").first

		headerLength = 0
		case basicHeader[0..1]
		when "00"
			# full 12 byte header
			parsed[:headerLength] = 12
		when "01"
			# 8 byte header
			parsed[:headerLength] = 8
		when "10"
			# just header and timestamp
			parsed[:headerLength] = 4
		when "11"
			# only basic header
			parsed[:headerLength] = 1
		else
			raise "Not a valid header"
		end

		parsed[:chunkStreamID] = basicHeader[2..7].to_i(2)
		parsed[:timestamp]     = charsToNum(raw[1..3]) if parsed[:headerLength] > 0

		if parsed[:headerLength] > 4
			parsed[:packetLength]  = charsToNum(raw[4..6]) 
			parsed[:msgTypeId]	   = charsToNum(raw[7])
		elsif parsed[:chunkStreamID] == 4
			parsed[:msgTypeId]	   = RTMP_AUDIO_PACKET
		end

		parsed[:msgStreamId]   = charsToNum(raw[8..11]) if parsed[:headerLength] > 8

		parsed

	end

	def handleRequest(streamid, header, request)

			response = ""
			stream = ChunkStream.find_by_id(streamid)

			case stream.stream_type
			when RTMP_AMF0_COMMAND
				cmd = RubyAMFParser.parse(request[header[:headerLength]...header[:headerLength] + header[:packetLength]])
				response = addHeader(RubyAMFParser.encode(CommandHandler.handle(cmd)),header[:chunkStreamID],Time.now)
		
			when RTMP_AUDIO_PACKET

				# what SHOULD happen:
				# parse each packet individually.  rework AMF codes to not just remove one char headers,
				# but store packets until ready to execute...

				File.open(MEDIA_STORAGE_PATH + "/" + stream.session.id.to_s + ".flvpart", "ab") { |f|

					f.write(FLVWriter.writeTag(request[header[:headerLength]..request.length], (stream.tag_count * 0x20), RTMP_AUDIO_PACKET))
					stream.tag_count += 1
				}
			end

			stream.save!

			response
	end

	def bytePad(bytes, count)
		#addBytes = []
		#(count - byteArray.length).times { |b| addBytes << "\x00"}
		#
		#addBytes.concat(byteArray)
		bytes.to_s.rjust(count,"\x00")
	end

	def numToOctet(num)
		num.to_s(2).rjust(8,'0')
	end

	def charsToNum(string)
		#string.reverse.unpack("H*").first.to_i(16)
		string.unpack("H*").first.to_i(16)
	end

	def binaryStringToChars(binaryString)
		Array(binaryString).pack("B*")
	end

	def numberToChars(number, bytes=1)
		# 'bytes' is number of bytes that should be returned

		hex = [number.to_s(16)]
		hex[0].insert(-2,'0') if (hex[0].length % 2 == 1)
		
		bytePad(hex.pack("H*"),bytes)

		#byteString.scan(/./).last(bytes).join("")

	end

	##################################################################
	#                                                                #
	#                       HTTP HANDLERS                            #
	#                                                                #
	################################################################## 

 
	# STEP 1A - handshake
	# For some reason, Flash calls /fcs/ident2 and actually looks for
	# a 404.
	post '/fcs/ident2' do
		404
	end

	# STEP 1B - handshake, continued
	# This is the real initialization.  Flash calls /open/1 and wants a 
	# session ID to be used in future requests.  It seems that it MUST
	# end in an \r\n line break.
	post '/open/1' do
		session = Session.new
		session.request = -1 # despite this request, the count will begin at /idle/:session/0
		if session.save!
			"#{session.id}\r\n"  # session id
		end
	end

	# STEP 2 - idle
	# After the handshake is approved, Flash will now ask for
	# /idle/<session_id>/0 -- but that last number will increment.
	post '/idle/:session/:i' do
		# we dont need to do much here - just let the client know that
		# we're still listening.
		increment
		"\x01"
	end 

	# STEP 3 - send
	# all requests from here on out -- until close/:session are either /send or /idle
	post '/send/:session/:i' do
		increment

		session = Session.find(params[:session])
		chunk_size = session.chunk_size || 128

		request.body.rewind
		requestbody = request.body.read

		# first request is 1537 bytes of nothing
		if (session.initialized == false) and (requestbody[0] == "\x03") and (requestbody.length == 1537)
			puts "***RECEIVED 1537 BYTES***"
			session.initialized = true
			session.needClearStream = true
			session.save!

			response = "\x00\x00\x00\x00\x01\x02\x03\x04" + (0...3064).map{1.+(rand(254)).chr}.join #1536 bytes of totally random nothing

			halt "\x01\x03" + response
		elsif session.initialized
			puts ">> REQUEST IS #{request.content_length} BYTES LONG"
			# this is an actual request that needs to be parsed.
			response = ""

			if session.active != true
				puts "SESSION NOT YET ACTIVE"
				session.active = true
				requestbody = requestbody[1536...requestbody.length]
			end

			# loop through entire request, seperating packets into streams;
			# process streams when done.  

			# this should be able to handle interleaved packets, AMF (will be executed at end),
			# and multiple audio tags sent at once.

			curPos = 0
			packets = {}
			while (curPos < requestbody.length)
				puts ">>>>" + requestbody[curPos..curPos+12].inspect
				header = readHeader(requestbody[curPos..curPos+12])

				# try to keep track of the various streams, whether they are active, and their TYPES
				puts "SESSION: " + session.id.inspect
				stream = ChunkStream.find_or_initialize_by_number_and_session_id(:session_id=>session.id,:number=>header[:chunkStreamID])
				if stream.new_record?
					stream.stream_type = header[:msgTypeId]
					stream.tag_count = 0
				end
				
				if header[:packetLength].nil?
					if header[:msgTypeId] == RTMP_AUDIO_PACKET
						header[:packetLength] = 64
					else
						header[:packetLength] = chunk_size
					end
				end

				currLength = header[:headerLength] + header[:packetLength]

				if header[:msgTypeId] == RTMP_AMF0_COMMAND
					x=chunk_size+header[:headerLength]+curPos
					while x < curPos + currLength
						requestbody[x] = ''
						x+=chunk_size
					end
				end

				stream.save!

				if packets.has_key?(header[:chunkStreamID])
					packets[header[:chunkStreamID]] << [stream.id,header,requestbody[curPos..curPos+currLength]]
				else
					packets[header[:chunkStreamID]] = [ [stream.id,header,requestbody[curPos..curPos+currLength]] ]
				end

				curPos += currLength + 1
			end


			packets.each do |k,v| 
				v.each do |packet|
					response += handleRequest(packet[0],packet[1],packet[2])
				end
			end

			puts "-------------------------------"
			puts "HEADER: "
			puts "Stream ID: "      + header[:chunkStreamID].to_s
			puts "Timestamp: "      + header[:timestamp].to_s
			puts "Packet Length: "  + header[:packetLength].to_s
			puts "Header Length: "  + header[:headerLength].to_s
			puts "MSG Type ID: 0x"  + header[:msgTypeId].to_s(16)
			puts "MSG Stream ID: "  + header[:msgStreamId].to_s
			puts "Chunk Size: "		+ chunk_size.to_s
			puts "-------------------------------"

			# BEFORE YOU DO ANYTHING, THE FIRST RESPONSE MUST CONTAIN A "CLEAR THE STREAM"
			# PING TYPE.  (0x04) - HEADER IS FOLLOWED BY SIX "00" BYTES.  
			# THIS CAN BE APPENDED TO OTHER RTMP/AMF DATA REPSONSES.
			if session.needClearStream
				# response += addHeader("\x04\x00\x00\x00\x00\x00\x00",2,session.created_at,true,false)
				response = "\x02\x00\x00\x00\x00\x00\x06\x04\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" + response #hardcoded clear stream with header
				session.needClearStream = false
			end
			session.save!
			halt "\x01" + response
		end
		session.save!
		"\x01" # if no other response

	end

	# STEP 4 - end
	# Session is over.  Delete it.
	post '/close/:session/:i' do
		increment

		FLVWriter.newFromFile(MEDIA_STORAGE_PATH + "/" + params[:session].to_s + ".flvpart")

		session = Session.find(params[:session])
		session.destroy

		"\x00"
	end
end

# models
class Session < ActiveRecord::Base
	# the session model
	has_many :chunkStreams
end

class ChunkStream < ActiveRecord::Base
	# the stream model
	belongs_to :session
end