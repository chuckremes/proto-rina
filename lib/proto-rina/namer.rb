require 'digest'

class ProtoRINA
  
  # Provides name registration and locating services.
  #
  # When a thread starts, we expect it to register itself here
  # with a requested name. The _Namer_ will record the registration
  # and make a unique-to-this-process name. This unique name should
  # be concealed from the registered process otherwise they might
  # leak it; it's no one else's concern so keep it secret.
  #
  class Namer
    def initialize
      @registry = []
    end
    
    # Let's each Application Entity (thread in this case) register
    # itself with the DAF under a name. This name will be recorded here.
    # The Namer will also generate a unique name to act as the
    # canonical name for the life of this process.
    #
    def register_ae(name:)
      # TODO: error checking, dupe checking, min/max length, etc.
      entry = { chosen: name, canonical: canonical(name) }
      @registry << entry
      nil
    end
    
    # For debug, pretty print the contents of our registry.
    #
    def dump
      pp @registry
    end
    
    private
    
    # Given a string, generates a unique hash of it. Find a better
    # algo... good enough for now.
    #
    def canonical(name)
      Digest::SHA2.hexdigest(name.to_s + now.to_s)
    end
    
    def now
      Time.now.to_f
    end
  end
end
