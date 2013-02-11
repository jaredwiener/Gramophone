class FLVWriter
	# class for actually writing FLV files

	def self.newFromFile (path)
		# this will find a file of concatenated FLV packets, and turn into a
		# playable FLV file.

		#f = File.open(path, 'rb')
		#f.seek(-4, IO::SEEK_END)
		#lastTagLength = (f.read).to_i
		#f.rewind
		#lastTagLength = (f.readline[0..4]).to_i
		#f.seek((0-lastTagLength), IO::SEEK_END)
		#lastTag = f.read

		filesize = File.size(path)
		lastTagLength = IO.binread(path,4,filesize-4).unpack("N").first

		puts "lastTagLength=" + lastTagLength.inspect

		durMixedEndian = IO.binread(path,4,(filesize-lastTagLength))

		puts "------------------------------------------"
		puts lastTagLength.inspect + '/' + durMixedEndian.inspect
		puts "------------------------------------------"

		#durMixedEndian = f.readline[0..4]
		dur = ((durMixedEndian[3] + durMixedEndian[0..2]).unpack("N").first.to_f/1000)
		#dur = durMixedEndian.unpack("C4").join.to_f/1000
		puts dur.inspect
		puts "------------------------------------------"

		amfData = RubyAMFParser.encode([
			"onMetaData",
			{"audiocodecid"  	=> 5.0,					# Nellymoser 8kHz mono
			 "duration"		 	=> dur,					# replace this number with duration in seconds (testaudio.flv is 16.416)
			 "audiodatarate" 	=> 15.899122807017543,
			 "audiosamplerate"  => 5500.00,				# 5500 is the audiorate from testaudio.flv
			 "stereo"			=> false,
			 "novideocodec"		=> 0.0,
			 "audiosamplesize"	=> 16.0,
			 "server"			=> "Gramophone Server: v0.01",
			 "canSeekToEnd"		=> true}		
		])

		header =  "FLV\x01" 							# how all valid FLV files start
		header += "\x04"								# audio file
		header += "\x00\x00\x00\x09"					# total size of header (always 9, apparently)
		header += "\x00\x00\x00\x00"					# previous header size (always 0, apparently)

		header += "\x12"								# this is METADATA (AMF)
		#header += [File.size(path)].pack("VX").reverse	# three-byte-long body length
		header += [(amfData.length)].pack("VX").reverse
		header += "\x00\x00\x00\x00\x00\x00\x00"		# 7 bytes of \x00 -- combination of time stamp and streamid

		# info on metadata keys/values here: http://livedocs.adobe.com/flex/3/html/help.html?content=Working_with_Video_17.html

		header += amfData
		header += [(header.length + amfData.length)].pack("N")

		newFLV = File.new(path[0..-5], 'ab') #changes .flvpart to just .flv
		newFLV.write(header)


		f = File.open(path, 'rb')
		f.rewind
		newFLV.write(f.read)
		f.close
		newFLV.close

		File.delete(path)
	end

	def self.writeTag(body, timestamp, type = 0x08)
		header = type.chr
		header += [(body.length)].pack("VX").reverse 	#body length

		if timestamp < 0xFFFFFF
			header += [timestamp].pack("VX").reverse + "\x00"
		else
			bigtc = [timestamp].pack("N")
			header +=  bigtc[1..3] + bigtc[0]
		end

		header += "\x00\x00\x00"							# streamid is always 0

		header + body + ([(header.length + body.length)].pack("N"))

	end

end