# What
Prototype of a RINA (Recursive InterNetwork Architecture) stack based upon the concepts in John Day's "Patterns in Network Architecture" book.

# Why
I'm still working to grok the layers and the relationships between functions within a layer. I need to code up some ideas to see what works and what doesn't work.

# Approach & Purpose
A few high-level aspects to this project include:
* All code will be in userspace
  * We can generate datalink frames via `bpf` in BSD and via RAW sockets in Linux. Not sure what to use for Windows yet, but I'm thinking about it.
* Code will be written in Ruby
  * Most of the other RINA prototypes on github (and elsewhere) are written in C, C++, or Java, presumably for *massive performance*. However, performance isn't my number one priority; understanding the system and its function is my priority. As a lone programmer, I can produce a lot more functionality in a high-level language like Ruby than I could in a systems language.
* Security
  * I'm interested in learning more about parser generators and how they can be used to `recognize` and `unparse` protocols in a secure and safe manner. See [langsec.org](http://langsec.org) for more information.

## Goal 1
Create a small RINA implementation that runs within a single process. Its purpose would be to mediate flows between threads thereby pushing the concurrency and parallelism chores onto RINA. Think of this as the `inproc` transport for ZeroMQ. Doing it in-process makes it simpler to debug and let's me exercise most of the "degenerate cases" (e.g. no directory lookup forwarding, minimal EFCP, no DIF enrollment).

The sample program will be a joke telling server and a joke listening client. The server will wait for incoming joke requests, accept the flow, tell a joke to the flow, deallocate the flow, and move on to the next request. 

Items exercised:
  * Name Registration
  * FlowAllocator
  * FlowAllocatorInstance
  * EFCP (for flow control, because a flow without flow control is _pathological_)
  * Flow accepting
  * Flow reading
  * Flow writing
  * Flow deallocationg
  * Minimal QoS support (zero-copy/reference-copy)

To run it:
`bin/run`
  
## Goal 2
Build on the code from Goal 1. Create a second IPCP in the same process. With two IPCPs we can now explore how an AP enrolls in another DIF. Some of the degenerate cases fall away, so we may have some directory service forwarding, message relay through the DIFs, and I don't know what else.

## Goal 3
Establish a flow between two processes on the same logical machine and exchange a message. Anticipate using POSIX shared memory or other IPC support like UNIX sockets for this purpose. Will require a library for the `Application Process` to define the RINA API, and a standalone daemon/process to run the `DIF`.

## Goal 4
Establish a flow between two processes on different logical machines and exchange a message. Anticipate generating ethernet frames for this purpose. Will build on `Goal 3` by adding a `DIF0` (my nomenclature) which is the DIF responsible for managing the datalink layer.

## Goal 5
Fuzzy... highly likely that there will be sub-goals to the above that I'm not even aware of yet. But for a third major milestone, I'll probably continue exploring the separation of mechanism from policy as it relates to the network stack. Potentially fun opportunities to play with QoS policies, make them pluggable, see how to aggregate like policies over flows, etc.

## Goal 6
Even fuzzier... probably want to see how to scale this down to work on a `SBC` (single-board computer like a RaspberryPi) and/or a microcontroller like an `Arduino`. Will need to work with my friends on the [Rubinius project](http://github.com/rubinius/rubinius) to see if that runtime will be able to (eventually) generate standalone code that can run on a microcontroller.

# Who
I'm just a curious guy who wants to see how this can work.


(c) 2019, Chuck Remes.
