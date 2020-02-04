# Setup a shared memory region along with a head and tail pointer.
# Spawn writer and reader threads (one each) and pass messages
# from one to the other.

require 'ffi'
require 'pry'

module FFI
  class Struct
    def address_of(field)
      Pointer.new(:uint8, self.pointer.address + offset_of(field.to_sym))
    end
  end
end
  
class SharedMemory
  extend ::FFI::Library
  ffi_lib ::FFI::Library::LIBC

#  IPC_CREAT = 0b001000
  IPC_CREAT = 001000
  IPC_RMID  = 0
  
  # key_t     ftok(const char *path, int id);
  attach_function :ftok,   [:string, :int], :int
  #  int       shmget(key_t key, size_t size, int shmflg);  
  attach_function :shmget, [:int, :size_t, :int], :int
  # void *shmat(int shmid, void *shmaddr, int shmflg);
  attach_function :shmat,  [:int, :int, :int], :pointer
  # int shmdt(const void *shmaddr);
  attach_function :shmdt,  [:pointer], :int
  # int shmctl(int shmid, int cmd, struct shmid_ds *buf);
  attach_function :shmctl, [:int, :int, :pointer], :int
  
  
  attr_reader :data, :size
  
  def initialize(path: "/Users/cremes/dev/mygit/proto-rina/README.md", key_id: 25)
    @key = ftok(path, key_id)
    puts "ftok key #{@key.inspect}, errno [#{::FFI.errno}]"
  end
  
  def allocate(size: 1024)
    @size = size
    @shmid = shmget(@key, @size, 0666 | IPC_CREAT)
    p @shmid, @key, @size, (0666 | IPC_CREAT)

    { shmid: @shmid, errno: ::FFI.errno }
  end
  
  def attach
    @data = shmat(@shmid, 0, 0)
    p @data, @shmid

    { return: @data, errno: ::FFI.errno }
  end
  
  def detach
    ret = shmdt(@data)

    { return: ret, errno: ::FFI.errno }
  end
  
  def deallocate
    ret = shmctl(@shmid, IPC_RMID, FFI::Pointer::NULL)
    
    { return: ret, errno: ::FFI.errno }
  end
end

# Given a +size+ of a shared memory segment measured in bytes,
# allocate a structure that will save the head and tail pointers,
# plus an array to track a pointer reference per slot.
#
# That is, each array slot holds a 64-bit pointer.
#
class RingBuffer
  class StateVector < FFI::Struct
    layout \
      :read_index,  :uint64,
      :write_index, :uint64
  end
  
  class RingBufferStruct < FFI::Struct 
    pack 1
    
    def self.setup
      self.class.class_eval do
        define_method :define_layout do |slot_count|
          layout \
          :state_vector, StateVector,
          :ring,   [:pointer, slot_count],
          :data,   [:uint64, slot_count * 2],
          :guard, :int64
        end
      end
    end
      
    def reset!
      self.read_index  = 0
      self.write_index = 0
    end
    
    def read_index
      self[:state_vector][:read_index]
    end
    
    def write_index
      self[:state_vector][:write_index]
    end
    
    def read_index=(value)
      self[:state_vector][:read_index] = value
    end
    
    def write_index=(value)
      self[:state_vector][:write_index] = value
    end
  end
  
  attr_reader :rb, :max_index
  
  def initialize(mask: 8)
    @bit_mask = 2**mask - 1
    @sm = SharedMemory.new
    pointer_size = FFI::Pointer.size
    
    RingBufferStruct.setup
    @max_index = slot_count = 2**mask
    RingBufferStruct.define_layout(slot_count)

    # create & attach shared memory segment
    @sm.allocate(size: RingBufferStruct.size)
    @sm.attach

    @rb = RingBufferStruct.new(@sm.data)
    field_base = @rb.address_of(:ring)
    
    # make an array of pointers to easily access each ring buffer slot
    @slots = slot_count.times.map { |index| field_base + (index * pointer_size) }
    
    @rb.reset!
    @slots.each { |slot| slot = FFI::Pointer::NULL }
  end
  
  # Make sure to allocate enough memory for a ring buffer with a slot count
  # that is a power of 2 plus the header
  def compute_buffer_size(bits:, pointer_size:)
    ring = (2**bits) * pointer_size
    ring += StateVector.size
  end
  
  # Will need to eventually rewrite to minimize the number of memory barriers
  # required to safely execute. Currently written for simplicity but by doing so
  # the code would need 3x or 4x as many memory barriers invoked.
  
  # Increment the index of ring buffer. Wraps around to front when index
  # exceeds total length; a cheap bitmask operation can do this when slot
  # count is a power of 2.
  def increment_index(index)
    (index + 1) & @bit_mask
  end
  
  def increment_read
    rb.read_index = increment_index(read_index)
  end
  
  def increment_write
    rb.write_index = increment_index(write_index)
  end
  
  def read_index
    # calling this requires a memory barrier
    rb.read_index
  end
  
  def write_index
    # calling this requires a memory barrier
    rb.write_index
  end
  
  def full?
    # calling this requires 2 memory barriers, one to read the write_index
    # and the second to read the read_index
    next_index = increment_index(write_index)
    next_index == read_index
  end
    
  def write(pointer)
    # should replace this with policy-based mechanism for when queue is full;
    # e.g. drop? block? overwrite?
    return false if full?
    
    @slots[write_index] = pointer
    increment_write
    true
  end
  
  def empty?
    # calling this requires 2 memory barriers, one to read the write_index
    # and the second to read the read_index
    write_index == read_index
  end
  
  def read
    # should replace this with the correct policy handling for when queue is empty
    return [false, nil] if empty?
    
    value = @slots[read_index]
    increment_read
    [true, value]
  end  
end



if $0 == __FILE__
  
  mask = 6 # Will allocate a ringbuffer with 2**mask slots
  rb = RingBuffer.new(mask: mask)
  secs = 5


  write_thread = Thread.new do
    puts 'Writer thread starting'
    puts "Writing values to array and enqueing in ring buffer"
    # Setup easy way to access each data pointer that will be written to
    # the ring buffer... stores integers for simplicity of testing right now
    base_pointer = rb.rb.address_of(:data)
    size = (2**(mask + 1))
    data_array = size.times.map { |i| base_pointer + (i * 8) }

    index = 0
    start = Time.now
    
    until (Time.now - start) > secs # loop for x seconds
      # write to array
      element = data_array[index % size]
      value = element.read(:uint64) + index + 1
      element.write(:uint64, value)
      rb.write(element)
      puts "wrote [#{value}] to #{index}"
      loop while rb.full? && (Time.now - start) <= secs
      index = (index + 1) % size
    end
    puts 'Writer thread exiting...'
  end  
  
  sleep 0.1
  read_thread = Thread.new do
    puts 'Reader thread starting...'
    
    # read array
    # data_array.each do |element|
    #   p element.read(:uint64)
    # end
    puts "reading from ring buffer"
    i = 0
    start = Time.now
    until rb.empty?
      success, pointer = rb.read

      loop while rb.empty? && (Time.now - start) <= secs
      puts "read [#{pointer.read(:uint64)}] from #{i}"
      i += 1
    end
    puts 'Reader thread exiting...'
  end
  
  [write_thread, read_thread].each { |thr| thr.join }
end
