#######################################################
#               RUBY AMF PARSER                       #
#           For use with Gramaphone                   #
#######################################################

class RubyAMFParser
	# lots of help here: http://wiki.gnashdev.org/AMF

	def new (args)
		#constructor if ever needed
	end

	def self.parse(parseString)
		result = []
		nextUp = {}

		nextUp[:value] = parseString
		nextUp[:totalLength] = 0

		i = 0
		keepGoing = true
		while keepGoing
			if nextUp[:value].length > 0 and isAMF(nextUp[:value])
				nextUp = decode(nextUp[:value])

				result << nextUp[:value]

				i += nextUp[:totalLength]
				
				nextUp[:value] = parseString[i..parseString.length]
			else
				keepGoing = false
			end
		end

		result
	end

	def self.isAMF(candidate)
		works = false
		unless candidate.nil?
			case candidate[0].ord.to_s(16).upcase
			when "0"
				#number 
				works = true if candidate.length>9
			when "1"
				# boolean
				works = true if candidate.length>2
			when "2"
				# string
				works = true if candidate.length>4
			when "3"
				# works = true if candidate.index("\x09") > 0
				works = true unless candidate.index("\x09").nil?
			when "5"
				# null
				works = true
			when "6"
				# undefined
				works = true
			when "8"
				#object
				works = true if candidate.index("\x09") > 0
			when "A"
				works = true if candidate.length > 5
			when "11"
				works = true
			end
		end

		works
	end

	def self.decode(parseString)
		# single byte header determines type
		# followed by a two-byte length - big endian

			#AMF0 TYPES
			result = ""
			case parseString[0].ord.to_s(16).upcase
			when "0"
				#number
				# result = makeNum(parseString[1..8])
				nums = ""
				parseString[1..8].scan(/./).each do |b|
					nums += b.ord.to_s(16) + " "
				end
				result = parseString[1..8].unpack("G") #double-precision, network (big-endian) byte order
				length = 9
			when "1"
				#boolean
				if parseString[1].ord != 0
					result = true
				else
					result = false
				end
				length = 2
			when "2"
				#string
				amfLength = makeNum(parseString[1..2]) #convert big endian value to Fixnum
				result = parseString[3..amfLength+2]
				length = result.length + 3
			when "3"
				#object
				objLength = parseString.index("\x00\x00\x09")
				idx = 1
				result = {}
				while idx < objLength
					keyLength = parseString[idx..idx+1].unpack("B*").join("").to_i(2)
					key = parseString[idx+2...idx+keyLength+2]
					idx += keyLength+2
					v = decode(parseString[idx..parseString.length])
					val = v[:value]
					idx += v[:totalLength]
					result.merge!({key=>val})
				end
				length = objLength
			when "4"
				#movieclip
				# This type is not supported and is reserved for future use
			when "5"
				#null
				result = nil
				length = 1
			when "6"
				#undefined
				result = nil
				length = 1
			when "7"
				#reference
			when "8"
				#ecma array
				length = parseString.index("\x00\x00\x09")
				idx = 5
				result = {}
				while idx < length
					# key is always a string, without the 0x02
					keyLength = makeNum(parseString[idx..idx+1])
					key = parseString[idx+2..idx+keyLength+1]
					idx += keyLength+2
					v = decode(parseString[idx..parseString.length])
					val = v[:value]
					idx += v[:totalLength]
					result.merge!({key=>val})
				end
				result
			when "9"
				#object end
			when "A"
				#strict array
			when "B"
				#date
			when "C"
				#long string
				amfLength = makeNum(parseString[1..2])
				result = parseString[3..amfLength+2]
				length = result.length + 3
			when "D"
				#unsupported
			when "E"
				#record set
				# This type is not supported and is reserved for future use
			when "F"
				#xml object
			when "10"
				#typed object
			when "11"
				# possibly a flag to switch to AMF3
				puts "***SWITCHING TO AMF3***"
				result = nil
				length = 1
				flag = "amf3" 
			else
				puts parseString[0].ord.to_s(16).upcase + " IS NOT A VALID AMF"
				puts parseString[0...parseString.length].scan(/./).map{|x| x.ord.to_s(16)}.join(" ")
				raise
			end
			{:value=>result, :totalLength=>length, :flag=>flag}
		#end
	end

	def self.encode(response)
		formatted = ""
		response.each do |obj|
			formatted += write(obj)
		end

		formatted
	end

	def self.write(obj)
		case obj.class.to_s
		when "Float" 
			# "\x00" + [obj].pack("c")
			"\x00" + [obj].pack("G") #double-precision, network (big-endian) byte order
		#when "Boolean"
		#	"\x01" + (obj)?"\x01":"\x02" #"ide fix
		when "FalseClass"
			"\x01\x00"
		when "TrueClass"
			"\x01\x01"
		when "String"
			"\x02" + splitNums(obj.length,2) + obj
		when "NilClass"
			"\x05"
		when "Hash"
			# encoding this as an object, but this could also be an ECMA array....
			#encoded = ""
			#obj.each do |k,v|
			#	encoded += write(k)[1..k.length+2]
			#	encoded += write(v)
			#end
			#"\x03#{encoded}\x00\x00\x09"

			# encode this as an ECMA array, *NOT* an object
			encoded = ""
			obj.each do |k,v|
				encoded += write(k)[1..k.length+2]
				encoded += write(v)
			end

			# the four 0 bytes are a hardcoded long -- this will need to be changed to
			# reflect the highest numeric index in the array, if there is a numeric
			# index in the array. 
			"\x08\x00\x00\x00\x00#{encoded}\x00\x00\x09" 
		else
			puts "***cannot encode #{obj.class.to_s}"
			puts obj.inspect
		end
		# remember to write the header at the END

	end

	private

	def self.splitNums(num,bytes)
		hex = [num.to_s(16)]
		hex[0].insert(0,'0') if hex[0].length % 2 == 1
		
		hex.pack("H*").to_s.rjust(bytes,"\x00")
	end

	def self.recreateByte(bits)
		# there has to be a better way to do this
		fullval = 0
		value = 1
		bits.reverse.scan(/./).each do |d|
			fullval += value if d == '1'
			value*=2
		end
		fullval
	end

	def self.makeNum(bytes)
		recreateByte(bytes.unpack('B*').map{|x| x.to_s}.join("")).to_i
	end
end