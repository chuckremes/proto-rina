require "rubygems"
require 'ffi'

module Shared
  extend FFI::Library
  ffi_lib FFI::Library::LIBC
  
  # Tries to execute a block. If the block return value is -1 then
  # raises a RuntimeException.
  # @param [String] what a String description of what we're trying to do
  # @yield an FFI mapped function to be executed
  # @yieldreturn [Fixnum] a numerical value, as returned by FFI functions
  # @return [Fixnum] the result of the FFI function
  def Shared.try(what="Shared::Mem operation")
    result = nil
    if block_given?
      result = yield
      if result == -1 then
        raise RuntimeError, "Error code #{FFI::Errno} in #{what}"
      end
    end
    return result
  end # Shared::try module function
  
  # Shared memory constants, as defined in sys/ipc.h
  IPC_CREAT  = 001000
  IPC_EXCL   = 002000
  IPC_NOWAIT = 004000
  SEM_UNDO	 = 010000   # Semaphore undo
  
  IPC_R      = 000400		# Read permission
  IPC_W      = 000200		# Write/alter permission
  IPC_M      = 010000		# Modify control info permission
  
  IPC_RMID	 = 0        # Remove identifier */
  IPC_SET		 = 1        # Set options */
  IPC_STAT	 = 2        # Get options */
  
  # Semaphore control constants
  GETNCNT	   = 3	# [XSI] Return the value of semncnt {READ} */
  GETPID	   = 4	# [XSI] Return the value of sempid {READ} */
  GETVAL	   = 5	# [XSI] Return the value of semval {READ} */
  GETALL	   = 6	# [XSI] Return semvals into arg.array {READ} */
  GETZCNT	   = 7	# [XSI] Return the value of semzcnt {READ} */
  SETVAL	   = 8	# [XSI] Set the value of semval to arg.val {ALTER} */
  SETALL	   = 9	# [XSI] Set semvals from arg.array {ALTER} */
  
  # Attaching functions for Shared Memory management
  attach_function :ftok,   [:string, :int], :int
  attach_function :shmget, [:int, :int, :int], :int
  attach_function :shmat,  [:int, :int, :int], :pointer
  attach_function :shmdt,  [:pointer], :int
  attach_function :shmctl, [:int, :int, :pointer], :int
  
  # Shared memory class.
  # @example Producer:
  #   msg_writer = Shared::Mem.new :access => Shared::IPC_W
  #   msg_writer.write(str)
  #   ...
  #   msg_writer.mem.write_array_of_float(ary)
  # @example Consumer:
  #   msg_reader = Shared::Mem.new :access => Shared::IPC_R
  #   puts msg_reader.read
  #   ...
  #   p msg_reader.mem.read_array_of_float(ary.size)
  # @author Paolo Bosetti
  class Memory
    attr_reader :mem, :id
    # Initializer. It prepares all the dirty stuff needed to have a 
    # communication endpoint. Also initializes the @mem attrivutes,
    # which holds a reference to a FFI::Pointer instance that can be used for 
    # more tricky message passing (_e.g._ C arrays).
    # @param [Hash] args the arguments hash
    # @option args [String] path the path endpoint (don't change it)
    # @option args [Fixnum] id an endpoint index, can use different for concurring operations
    # @option args [Fixnum] len the reserved memory area in bytes
    # @option args [Fixnum] mode creation mode. See man shmget
    # @option args [Fixnum] access access mode. See man shmat
    def initialize(args={})
      @cfg = {
        :path   => "/Users/cremes/dev/mygit/proto-rina/README.md", 
        :id     => 25,
        :len    => 1024,
        :mode  => Shared::IPC_CREAT, 
        :access => Shared::IPC_W | Shared::IPC_R
      }
      @cfg.merge! args
      @key = Shared::try("ftok") {Shared::ftok(@cfg[:path], @cfg[:id])}
      @id  = Shared::try("shmget") {Shared::shmget(@key, @cfg[:len], 0666 | @cfg[:mode])}
      p @id, @key, @cfg[:len], (0666 | @cfg[:mode])
      @mem = Shared::shmat(@id, 0, @cfg[:access])
      p @mem, @id
    end
    
    # Closes the shared memory area end frees its content.
    def close
      Shared::try("dhmdt") {Shared::shmdt(@mem)}
      Shared::try("shmctl") {Shared::shmctl(@id, Shared::IPC_RMID, nil)}
    end
    
    # Read len bytes.
    # @param [Fixnum] len the number of bytes to be read
    def read(len=nil); @mem.read_string(len); end
    
    # Writes a string len bytes.
    # @param [String] str the string to be written
    # @param [Fixnum] len the number of bytes to be read
    def write(str, len=nil)
      raise ArgumentError, "str must respond to :to_s" unless str.respond_to? :to_s
      @mem.write_string(str.to_s, len)
    end
    
  end #Memory class
end

sm = Shared::Memory.new
p sm.write('hello')
p sm.read('hello'.size)
