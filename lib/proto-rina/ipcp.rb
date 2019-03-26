require_relative 'namer'

class ProtoRINA
  
  # The main workhorse of this prototype.
  #
  # Instantiates and manages all required services to provide in-process
  # communication. The communication is between threads so I'll still call
  # it IPC but now it means Intra-Process Communication.
  #
  class IPCP
    attr_reader :namer

    def initialize
      @started_flag = false
    end
    
    # Boots the process. Returns immediately to the caller and does not
    # block.
    #
    def start
      # ||= isn't thread-safe... fix later
      @thread ||= Thread.new { bootstrap }
      sleep 0.01 until @started_flag
      self
    end
    
    def bootstrap
      @namer = Namer.new
      @started_flag = true
    end
  end
end
