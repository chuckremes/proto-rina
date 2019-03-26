require 'pp' # for debugging

require_relative 'proto-rina/ipcp'

class ProtoRINA
  class << self
    
    # Debug via printf, lol
    def dump
      @instance.namer.dump
    end
    
    def start
      # intended to be a singleton
      @instance ||= IPCP.new.start
      nil
    end
    
    def register_ae(name:)
      # replace this with delegation/forwarding later
      @instance.namer.register_ae(name: name)
    end
  end
end