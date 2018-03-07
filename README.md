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
  * I'm interested in learning more about parser generators and how they can be used to `recognize` and `unparse` protocols in a secure and safe manner. See langsec.org for more information.

## Goal 1
Establish a flow between two processes on the same logical machine and exchange a message. Anticipate using POSIX shared memory or other IPC support like UNIX sockets for this purpose. Will require a library for the `Application Process` to define the RINA API, and a standalone daemon/process to run the `DIF`.

## Goal 2
Establish a flow between two processes on different logical machines and exchange a message. Anticipate generating ethernet frames for this purpose. Will build on `Goal 1` by adding a `DIF0` (my nomenclature) which is the DIF responsible for managing the datalink layer.

## Goal 3
Fuzzy... highly likely that there will be sub-goals to the above that I'm not even aware of yet. But for a third major milestone, I'll probably continue exploring the separation of mechanism from policy as it relates to the network stack. Potentially fun opportunities to play with QoS policies, make them pluggable, see how to aggregate like policies over flows, etc.

## Goal 4
Even fuzzier... probably want to see how to scale this down to work on a `SBC` (single-board computer like a RaspberryPi) and/or a microcontroller like an `Arduino`. Will need to work with my friends on the [Rubinius project](github.com/rubinius/rubinius) to see if that runtime will be able to (eventually) generate standalone code that can run on a microcontroller.

# Who
I'm just a curious guy who wants to see how this can work.


(c) 2018, Chuck Remes.
