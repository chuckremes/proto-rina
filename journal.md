# 20190211
This is my first official journal entry. The purpose of the journal is to record ideas on how to engineer and implement RINA. I have been thinking off and on about how to handle this implementation for about a year, but I haven't recorded any of my thoughts. I now find myself having to rediscover ideas and concepts that I had previously thought through. That has annoyed me. Time to write them down.

#### Layer1 / Layer2 hardware / Embedded
I know the concept of the OSI layers is outmoded with RINA but it's useful shorthand for the rest of the world to understand certain concepts. I've been thinking about embedded applications of RINA and of course one of the first would be as a Layer2 hardware device or network interface controller.

A PHY is the layer1 device. It handles translation of the layer2 commands into signals on the wire, EM signals over the aether, optical signals over fiber, etc. Layer1 is completely software protocol agnostic.

So I'm wondering how hard it would be to marry an existing PHY with a RISC-V and/or FPGA implementing RINA.

The "Specification for SHIM Processes over 802.1Q" is an interesting resource for this idea. In short, the VLAN tag field is used to contain the RINA DIF address. Wired ethernet is apparently still considered an unreliable medium. This makes sense in a broadcast or hub configuration but as we know most ethernet is deployed in a switched configuration which makes it effectively a hub & spoke setup with point-to-point comms.

Regardless, it's an interesting thought exercise to imagine how the RINA machinery would scale down to a MAC (Media Access Controller) chipset. What would flow allocation look like? Would it just contain a single QoS entry like the SHIM example? (Probably.) Would addresses be hardcoded at this level or would each piece of hardware handle enrollment into the LAN-wide DIF and wait for an address assignment? The bootstrapping process of this low-level DIF is a neat little problem.

I've been looking at FreeRTOS.org for inspiration on how to embed RINA software (hi, Jeff!). I'm not sure yet what kind of hardware runs a NIC so I'm in the early stages of figuring this out.

#### Data Tape
John Day and I have corresponded via private email. The last of these communiques is probably 9 or 10 months ago. In our dialogue he would sometimes refer to an efficient way to implement RINA by framing the problem using some old-style computer terminology. In the olden days the computer was programmed by a tape or punch cards much like a player piano. There was little random access memory so the computer was quite smart about reading its inputs and passing the data forward to future functions.

His regular reference to this idea had me puzzled until I started investigating a practical implementation using Ruby. Ruby is not a systems language. It's (usually) interpreted, has a runtime, contains a garbage collector that can't be disabled, and in general is a poor choice for embedded applications. But it's high level enough that I feel it's productivity benefits outweight any performance (cpu or memory) deficiencies.

So back to the idea of a data tape and RINA. At the most basic level, the idea would be that once a NIC DMAs (copies via direct memory access) a RINA packet from Layer1 into system memory, that should be the one and only copy ever made (ignore SDU protection for the moment). So the SDU would be copied into a ring buffer and ownership of that buffer would move from the NIC to the 1-DIF (NIC is 0-DIF because we're all C refugees and count from 0). 

This buffer would be processed by the EFCP and any protocol components at this level would be deciphered to determine next steps. Assuming the SDU is destined for an (N+1)-DIF, the buffer ownership would be transferred to the successively higher DIFs with no copying. The software would be relying on the set-and-test functionality built in to the local hardware (assuming preemptive tasking like interrupts) or by yielding (assuming some kind of cooperative tasking).

Another way to look at this same setup is on a process by process basis. Assume that each process has its own stack (program counter) and a small local heap for temporary work storage. However, it has a shared heap (via POSIX or SysV shared memory) that is shared by all RINA processes. Efficient! Plus this is probably how most of the userspace high perf stacks are implemented (cilium, ..., etc).

Where I'm still unclear is when and how that buffer is finally returned to the original incoming ring for reuse. If a userspace application could hang on to the buffer reference forever, then we'll need to allocate new buffers at the lower level which kills performance. I'll need to look at how the userspace stacks solve this tension.

Obviously the idea of SDU protection destroys the zero-copy approach. If each DIF is encrypting outgoing SDUs then the buffers will be copied at each layer. With the trend being to move everything from HTTP to HTTPS, a similar trend would probably be prevalent in RINA where each DIF does provide its own encryption. I think the days of plaintext transmission are long gone. This is even true for IoT (Internet of Things) traffic (or maybe *especially true*?).

BTW, I'm not certain at all that this is John's suggested approach. It's my guess on how to interpret his suggestion.

#### Bootstrapping
For the longest time I avoided looking at the `rlite` implementation. I didn't want it to pollute my own ideas on how to implement the stack. I only recently have looked at the code (i.e. last few days). I haven't gotten past the README and already it confirmed a few conclusions I had come to on my own.

I've been long concerned with how to bootstrap the RINA stack. For example, how does the first application in a DIF announce itself, find itself alone, and then complete the DIF initialization. I puzzled over this for a while.

Ultimately, I decided that the system itself (the operating system) should proactively bootstrap at least 2 DIFs. The 1-DIF would handle the NIC interaction. The 2-DIF would be available for applications. Higher level DIFs could be created on the fly from this point forward, but the original 2 DIFs would be present every time.

The `rlite` README pretty much confirmed this approach.

For my proof-of-concept, I'll probably just create the 2-DIF for intra-host communications. Lots to explore here.

# 20190213
#### Embedded
Thinking a little bit more about the embedded space. Discovered that there are some decent choices for high level languages that can run embedded. Specifically, we have Lua (eLua), Python (ePython), and Ruby (mruby). Of course, these are only suitable for 32-bit processors primarily because of overhead. Each requires a runtime and the concomitant additional RAM to hold it.

For the 8-bit controller space, my guess is that it will need to be custom hardware that is RINA aware. Doubtful that there would be sufficient horsepower or RAM to run even an optimized software version of RINA at that level. I don't know this for fact... I'm still quite ignorant of the embedded space but this is the impression I'm getting from my current research. I should look for TCP/IP stacks that run on 8-bit. If that more complex stack can run there then certainly a simpler RINA stack could too.

Also thought a bit about addressing for this space. I think a single byte is more than enough. If there are more than 255 devices that are vying for enrollment in a DIF, then we'll need a higher level DIF to overlay it and provide routing between them. Certainly for 8-bit controllers this could happen but we'd probably want the 2-DIF to be created and managed by a 32-bit controller. Again, I'm ignorant.

Jeff has indicated willingness to translate code written in higher level languages to C. Nice of him. Before this project is done, I'm certain I'll have to dust off my C skills from yesteryear.

#### Next Steps
I need to reread the Reference Model docs that Day & Co wrote. Now that I've decided on a bootstrapping approach, the obvious thing to do here is to write a minimal implementation that runs on a single host probably via shared memory. I can stub out several of the components like EFCP which aren't necessary. Will they be no ops? Don't know yet.

But certainly I'll need a Flow Allocator, an Enroller, Directory Services, and other RIB-like processes. Doubtful I'll need an RMT for the first PoC (proof of concept) though if I want to experiment with multiple DIFs on one box then the RMT becomes important again. Same for a Fragmenter/Reassembler since the DIFs may not agree on max SDU size thereby necessitating that additional work.

#### Directory Services & Addressing
It occurs to me that when DIFs map addresses between each other for routing that this mapping is essentially an ARP table.


# 20190215
#### Languages
Forgot Crystal as a potential candidate. Benefit of Crystal is that it compiles to machine code and has no runtime component. It can probably target less capable microcontrollers as a result. Also, it's Ruby-like syntax is familiar to me. Lastly, it has first-class support for C structs/unions so manipulating bits & bytes is pretty easy.

#### Ruby Note
To minimize allocations and GC overhead, design all the "functional" aspects of the code to be classes with class methods. They'll allocate upon loading so their memory footprint is fixed. Anything that will maintain state will obviously need to be allocated via `.new` so care should be taken to minimize that requirement. Instead of Strings, use Symbols. Use Constants. Preallocate any arrays, hashes, or other data structures used for local book keeping.

#### Insights
While reviewing the reference model for the umpteenth time, this section jumped out at me again:

```
Consideration in the design of a DAF should be given to making the OIB Daemon the only generator of application SDUs to the underlying DIF.  This not only allows better optimization and control, but facilitates the shift from an IPC model to a programming language model.  Hence, the work of the DAF can be expressed entirely in terms of operations on the RIB.

There is considerable literature on distributed databases that can be drawn on here.
```
Slightly rephrased, the DAF would define operations on its local RIB to CRUD data, perform a calculation, move data from A to B, etc. The DAF would write to the RIB and the RIB itself would generate the SDUs to remote locations. I believe this means the DAF itself wouldn't be reading/writing from the remote name but would use the RIB as a proxy object or like a write-through cache?

I think the real insight to be gained here will be to actually review the literature on distributed databases. I'm curious to know what their APIs look like from the perspective of the local user.

Perhaps ask Day or the mailing list for good examples of this literature.

# 20190219
#### Enrollment
```
5.5 DAF Enrollment
For an application process to join a DAF, it must be enrolled. Enrollment is carried out by the DAF Management task of the DAF infrastructure. Enrollment begins with an application process establishing an application connection with a member of the DAF. Once this management connection is created and the new member has been authenticated, the new DAP must be initialized. This may include but is not limited to the following operations:

1) Determining the current state of the new member (which may be a returning member);
2) Determining the capabilities of or assigning capabilities to the new member;
3) Assigning one or more synonyms to the new member for use with in the DAF;
4) Initializing static aspects of the DAP, perhaps including downloading code; and
initializing any DAF related policies;
5) Creating additional connections to support distributed RIB operations;
6) Initializing or synchronizing the RIBs; etc.
```
Figure 10 in that same section is very interesting. Its accompanying text clarifies the pictures, so the picture alone is insufficient.

In RINARefModelPart2-2, section 2.6.2, it discusses Shim DIFs and bootstrapping.
```
There is also the null case or bootstrap case, where a processing system is joining is first DIF. There are basically 3 cases to be considered here:
1) The use of a Shim DIF: For existing legacy media protocols8, RINA employs a Shim DIF. A Shim DIF provides the minimal functionality necessary to make an existing media standard have the same API behavior as a DIF with the properties of this media. A Shim DIF makes no attempt to “enhance” the existing media protocol. In this case, enrollment will follow the procedures of the legacy protocol. Normal DIF operations will work above that.
2) A DIF operating directly on point-to-point media: In this case, we must assume that there is either some ad hoc first PDU or that the process on the end of the point-to-point media, i.e. a wire, is expecting a RINA enrollment procedure. This will begin with CACE-Connect, also referred to as an M-Connect. Given these conditions the procedure can progress with normal enrollment.
3) A DIF operating directly over a multi-access media: In this case, we must assume that some unique identifier, e.g. an equipment serial number, is available to distinguish correspondents at the other “end” of the media. Either an ad hoc first PDU will carry this information or the “other ends” will be expecting a CACE- Connect PDU with this “unique identifier” as the Destination Application name. (The Source Application name will also have to be known to be unique within the scope of the media.) The source unique identifier must identify the IPC Process that is requesting to join the DIF. The destination unique identifier may name either the DIF being joined or an IPC Process that is a member of the DIF.
This exchange can now be used to either create a DIF on top of the media or join an existing DIF using the normal procedures, including the assignment of addresses within this DIF. However, note that the “unique identifiers” will still be required to distinguish traffic between different DIFs on the same media and within the scope of the media. There is, in effect, a very minimal Shim DIF over the multi-access media itself.
```

#### DIF Allocation
RINARefModelPart2-2, section 2.6
```
While networks can be constructed by external ad hoc means, the DIF-Allocator provides the means for the recursive construction of networks organically based on user demand.
```

#### Relaying
RINARefModelPart3-1 180617
No matter how many times I read the spec, this passage is one of the most important.
```
Because there can be more than one DIF of the same rank, there is no direct IPC between different (N)-DIFs, i.e. DIFs of the same rank, without relaying above.  IPC between DIFs of the same rank within the same processing system must use either an application process with only local knowledge (sometimes called a protocol converter), or by an application process with knowledge of a wider scope e.g. relaying by an IPC Process of a (N+1)-DIF.
```
Think of it this way. A single host probably has one ethernet port. So, we'd have a "DIF-0" to manage it. Another host on the same LAN would have the same configuration, so there's another "DIF-0" there. These are DIFs of the same rank. We would view these as point-to-point links in a modern switched ethernet environment. They would all enroll into DIF-0 across the LAN.

A process on that host that needs to communicate elsewhere will likely enroll as a member of DIF-1. For DIF-1 on HostA to communicate to a process on HostB, DIF-1 must use DIF-0 to send a message and the receiving DIF-0 will relay to its local DIF-1 to deliver the message. This is an example of (N)-DIF using (N-1)-DIF for relay.

That's probably the common case. 

Now let's look where there are DIFs of the same rank on the same host. There could be a DIF-0 for ethernet and a DIF-0 for wireless. Both of these DIFs will enroll into their respective "ethernet DIF-0" and "wireless DIF-0" layers. If an application on "ethernet DIF-0" needs to communicate to an application available on "wireless DIF-0", then there must be a DIF-1 that has sufficient scope to encapsulate both DIF-0s of the same rank. It will act as the relay to deliver the message.

It's a bit mindbending because we don't typically think of "going up" the stack to route!

# 20190221
#### EFCP and State Vector
Just a reminder to myself that a "state vector" is nomenclature unique to the RINA documentation. No one else seems to call it that. In the IP world, it's called a Transmission Control Block (TCB). 


# 20190227
#### Minimal Viable Product (MVP)
What's the minimum I need to do to get some `RINA` action?

My first thought is that instantiating a DIF is probably the MVP. However, a DIF without users is useless and therefore boring.

My second thought is that insantiating a DIF and having a single AP enroll in it is probably more interesting. That's at least somewhat useful and allows me to verify that enrollment and its dependent components is somewhat fleshed out (at least for local users). Better but still somewhat useless.

My third thought is that I need to have two APs enroll and exchange some messages. Ah! Useful!

So that shall be my target. I will:
1. Instantiate a single DIF on a host
   * Create the minimal required services to support
     * Enrollment
     * Service discovery / lookup
     * SDU Protection
     * Flow instantiation with a simple QoS
     * Bidrectional message exchange
2. Create two application processes that understand how to
   * Enroll in a DIF
   * Open a flow
   * Write a message
   * Read a message
   * Close a flow

On second look, this is quite a bit of work. I've ruminated long enough on design, how all of these pieces fit together, etc. I have many unanswered questions. I can no longer answer these questions by merely thinking about them and reviewing the reference model for the umpteenth time. I need to engineer and get my hands dirty. This hands on approach will cement my understanding and open practical avenues for answering my outstanding questions (most of which I haven't recorded here).


#20190228
#### Flurry!
After my writings last evening I spent the time walking home from the train thinking on some concrete steps. I suddenly realized that I had not picked the simplest MVP.

A little backstory. I was involved with the `ZeroMQ` project almost from its inception. I got to know Pieter Hintjens fairly well and met up with him on several occasions when he traveled through Chicago. I wrote the Ruby FFI bindings for the zeromq project and have maintained it now for many years.

One of the most useful aspects of the zeromq library was its concepts of transport independence. One could use `inproc`, `ipc` or `tcp` without changing any code at all beyond the URI for specifying the source/destination address (it now offers `pgm`, `epgm`, and `vmci` as additional transports). In this case, `inproc` was utilized for sending messages between threads. The `ipc` transport utilized UNIX domain sockets for intra-host communications. The other transports are self explanatory.

It's the `inproc` transport that fueled my imagination last night. The very simplest thing I could create would be a DIF that is in-process that acts as intermediary for different threads within that process. Enrollment gets very simple. SDU protection is unnecessary because the SDU never leaves the DIF.

I searched my memories for any mention of this in the `Patterns` book or any of the reference model. I don't recall it but I'm certain it's in there. This approach of applying the pattern is probably considered a "degenerate case." However, that does not mean it has no use; on the contrary, this is very useful!

So my new MVP will likely aim to provide an in-process DIF. I avoid all of the complexities of setting up POSIX (or SysV) shared memory and can rely on simpler mechanisms. Directory and service lookup should also be quite simple. There's obviously no need to worry about EFCP, RMT, or any related issue (or is there?).

When I get this working, it may provide a simpler approach for parallelism (and concurrency) within a single process. Regardless, it will give me confidence in the external API (open_flow, close_flow, read, write, etc.) which can be applied to a larger proof of concept at a later date.

And most wonderful of all is that this should allow for scaling transport from within a single process all the way to distributing the process across many hosts and many miles (or kilometers if you prefer). The coding approach should be unchanged since the API should be the same.

Additionally, the recursive nature of RINA makes the scaling dead simple. The in-process DIF can directly deliver messages to other threads within that process since they are all likely to be members of the DIF. If two separate processes need to collaborate, we'll need a lower ranking DIF that can act as transport between them. Hmmm, somehow this feels opposite to intentions... generally when two DIFs of same rank need to talk, the system somehow needs to create a DIF of a higher rank that they can both join. Will need to see how this shakes out in practice.

#### Physical Layout
For this newly imagined MVP, I'll have a `lib` directory. Within it will be a `proto-rina-client` folder which will handle all of the instantiation for in-process DIF bootstrapping. Initial implementation will probably use a mutex for synchronization but ultimately I'll want to implement some kind of ring buffer set so no message copying is necessary. 

#### Zero Copy
Interesting thought that just occurred while writing that last sentence above. When imagining how to do this to be language agnostic, it always comes down to preallocation of C structs via malloc (or similar) and passing bytes around. However, within a process that is completely unnecessary. Just pass references. This makes it much simpler for a managed language like Ruby too and the way the messages are shared is just an implementation detail within this DIF. The reference model goes to great pains to avoid nailing down *how* this should work, so intra-DIF it can probably just be anything (like reference sharing).

#### Physical Layout Again
Now that the interlude is over, back to this. Anything more to say? Hmmm, it's probably best to layout the files to correspond to the main components of a DIF like enrollment, CDAP, FlowAllocator, etc. I don't have a better idea at the moment so I'll brute-force it to get it running and then refactor.

Remember!
1. Make it work!
2. Make it _correct_!
3. Make it fast (and small).

I'll try not to get ahead of myself here.

#### Class Design
My understanding of the DIF concepts leads me to believe that only a few of the components maintain any kind of state. Most of the work is transformative in nature where bytes (or a reference) passes through and some work is performed on it.

So I think most of the classes will be written as Ruby classes containing only class methods. Mostly functional in nature (e.g. given same inputs, always produce the same outputs).

A few classes will be specifically allocated. 

I assume that most of the structures for maintaining state will be allocated at startup and fixed for the duration of the program's life. 

Obviously, any heap allocated memory should be purely for the use of the local process. Shared memory should only contain fixed structures for the efficient sharing of data between DIFs on the same host.


# 20190304
#### Greatest Hits
"A network without flow control is pathological." - John Day, 20151210, RINA mailing list

#### Further Design Thoughts
I have to remind myself sometimes that my 3-step process listed above doesn't contain a zeroeth step: `0. Ignore your experience`.

The reason I write this is because I have been thinking about the initial implementation all in a single process. There are M writers and N readers from one perspective, but there aren't many efficient implementations of data structures that can handle that kind of access pattern. I lean on my experience with ZeroMQ here where I recall that we oftentimes ran into a fast producer / slow consumer situation. The queues would fill up and put backpressure on the producer to slow down.

When looking at implementing such a setup here, I note that each thread is a reader and a writer. The RINA thread itself is too. A naive implementation would slap a single mutex on a data structure that all M worker threads were read/write from/to but I'm not naive. I'm not going to jump to the ultimate solution here because I don't actually know what it is. However, I suspect that each worker thread should have a separate read queue from its write queue. A worker that writes 99% of the time and reads 1% (or never) shouldn't have the same allocation of resources if possible; they might just be wasted.

Perhaps the QoS cube can influence this?

Anyway, since this is all in-process, it occurs to me that allowing a writer to queue within the RINA thread is somewhat non-sensical. Why make the RINA thread handle this queue management / resource allocation issue when the worker thread has the most localized knowledge of its requirements? I'd say that we want to implement some kind of flow control even within the process to prevent fast producers from overrunning slow consumers.

So how do we do this? I think the answer lies in the API. Presumably we will have `flow_open`, `flow_close`, `flow_read`, and `flow_write` (it remains to be seen if we have the `start`/`stop` mechanisms described by Day). If a fast producer is calling `flow_write` in a tight loop, it should get back a failure if it attempts to overrun its consumers. The producer can then choose to either drop the message itself or block while waiting for the consumer to catch up.

A practical implementation of this would look like a 1-element buffer. When a writer has written, it can't write again until RINA has delivered that message. Plus, every reader has a 1-element buffer. If there is already an element waiting, no other message can be delivered. Of course, this is all influenced by the QoS cube. If the cube specifies that newer message have priority over older messages, the buffer would be overwritten for the slow consumer.

One of these days I'm going to have to dig in to what a QoS "cube" looks like. I recall investigating the ideas behind it many months ago and discovered that it's probably a multi-dimensional cube with dimensions like jitter and latency. I forget what the others are...

Ah, [here's an article on Quality of Service](https://infogalactic.com/info/Quality_of_service) that mostly defines it as bit rate, delay, jitter (delay variability), packet dropping probability, and bit error rate. I see 5 dimensions here. Looking further down the page, it's alternately defined as throughput, dropped packets, errors, latency, jitter, and out-of-order delivery. Now 6 dimensions. I wonder what the difference is between "dropped packets" and "errors." Ah, dropped packets is kind of a superset of errors. A packet may be dropped due to a bit error OR if the intermediate buffers are full.

Anyway, will need to look into this deeper soon. I do believe that QoS is relevant even in-process so I'd like to get that correct.

Time to start coding? Nervous...

#### Coding
Just created some directories and setup the rspec infrastructure. What's the simplest thing I can get to work? Probably have the DIF bootstrap itself and setup a few things, though that's boring. The simplest useful thing I can do is informed by my earlier discussoin above on this topic... get two threads to exchange a message with each other. This will require enrollment, flow allocation, and message delivery.

*Really nervous* now.

#### Random QoS
Should QoS include safety dimensions like encryption? What about compression or lack of it? For multimedia it seems that would be useful... don't compress this again because it's already been compressed!


# 20190305
#### Collaborators!
My good friend Donovan Keme (@digitalextremist) and I are going to collude on this project. Can't wait.

#### Enrollment Again
The reference model refers a few times to the fact that a DAP may be enrolled in multiple DIFs. The API (flow_allocate, flow_deallocate, flow_read, flow_write) and its arguments don't show any reference to a DIF. Therefore, I assume the handle/reference to the API itself is coming *from the DIF*. This might be wrong but let's roll with it for now.

So, before a flow can be allocated, one must first be enrolled in a DIF. Need to look through the docs and see how this works because it is probably the first thing I need to implement.

#### Review of Ref Model Again
Looking at the reference model again it's getting clearer what these things are called. An Application Process (AP) may have several Application Entities (AEs) that communicate with a DIF. The AP, either singly or as part of a group, is considered a DAF. For members of a DAF to communicate, they need to use the underlying DIF. To use the numbers, an (N)-DAF uses the (N-1)-DIF for IPC. 

Another way to look at this from a single process standpoint is that each thread in the process is potentially an AE. Collectively they are a DAF that may need to coordinate to provide some service. They have a Distributed Application Name (DAN). Actually, two. One is a multicast name that refers to the collection and a second one that refers to a specific entity (so at least two maybe more). Anyway, for the DAF AEs to enroll, they need to use the facilities provided by the (N-1)-DIF.


# 20190306
#### Enrollment Again
This will be a popular header until I solve this problem.

Reference Part3-2 covers flow allocation. For a process A to talk to process B, it always seemed like there was some magic involved in allowing the DIF to know who A and B are. Turns out that there is a registration process that I had previously overlooked. In other words, processes A and B need to register with their local DIF to indicate that they are available.

When A wants to contact B, it sends an Allocate Request via an API call to the local DIF's IPCP. The IPCP hands this off directly to the FlowAllocator. The FlowAllocator allocates an instance (FAI) to handle the lifecycle of this connection. The FA (which knows about *all connections*) determines if the request can be accommodated from a resource perspective. If no, return an error. If yes, create the FAI and let it generate a Create PDU which leads to an EFCP instance being created. What I wrote in this last paragraph is my paraphrase of the RefModelPart3-2 section 2.2.2; see there for the rest of the story.

#### Minor Eureka
Just had a little eureka! moment. When reading the Enrollment-BasicSpec180610.doc it finally dawned on me that Enrollment is how an IPCP connects to an existing DIF. All this time I thought enrollment was how an AP joined a DIF. Wrong!

The AP registers itself with some omniscient DIF Mgmt System (DMS in the docs). That same registration interface should provide the handle/reference to the DIF that the AP wants to use for IPC. The AP, either singly or multiply, is viewed as a DAF. This DAF stuff has confused me because it's an "enhancement" from the architecture proposed by the book and only shows up in these later writings. It has muddied the waters for me. Writing this now has me scratching my head wondering why the AP doesn't have to enroll in the DAF? But eventually you get to this infinite regression problem where someone somewhere just _springs into being_ without any enrollment at all. Just... unclear. Might have to ask on the mailing list about this.

I hope my eureka was real. I might be getting excited about drawing the wrong conclusion. :)


# 20190318
#### Vacation
I was on vacation all of last week and had grand plans to do some programming. I didn't actually write any code or any journal entries though. I found myself with my 3-month old in one arm while I used the other to toss a ball to my 2-year old. So, I did programming in the sense that I was civilizing my 2-year old and loving my 3-month old. Not what I had planned but fulfilling and rewarding nevertheless. I squeezed in a little thinking during that time.

#### Science vs Engineering
John Day goes to great pains in the Reference Model write-up to warn against using the descriptions as an engineering outline. He is correct to do so. His reference model and overall `RINA` work is _science_ whereas I intend to perform some feats of _engineering_ here.

Looks to me like `Step 1` of the engineering effort will be to create process-wide `naming service`. This service will allow threads to register themselves as they bootstrap and be assigned a name and address. I'll need to reread the naming chapters again but I think it will be relatively straight forward.

Eventually, this in-process naming service will know how to delegate to the host-wide naming service to find services in other processes on the same host. Further, that host-wide naming service will eventually be augmented to pass inquiries via the (N-1)-DIF to other hosts to find services. So none of this is wasted effort; it's a repeatable structure that works at difference scopes (process, host, LAN, WAN). Beautiful, really.

The repeating structure is described by Day but the engineering challenges and interfaces get little to no discussion. I'll be working my way through that here. I've said it before and will say it again: this is a large-scale "rubber ducking" session to guide my thoughts and refine my ideas. I don't have a collaborator to discuss these things in real-time, so my own psyche will have to do.

#### Zero-copy
I am probably getting ahead of myself here. For managed languages like Ruby, we can still use fixed-size ring buffers and similar structures to share data between threads. The initial code will probably just use a `Queue` or a mutex-wrapped array to keep things simple. Ideally there will be no object copying in-process. 

I have thought that the delimiting function could potentially act as a mechanism to encode Ruby objects to a primitive form (JSON, netstring, whatever) for transfer out of process. Further thought has pointed to the SDU Protection function as the right place. The reason it's not clearly in one or the other because the delimiting function needs to be aware of the max PDU size but this happens earlier in the pipeline from the Protection function. In between them lies the RMT (Relaying and Multiplexing Task) which determines if the PDU will be mapped from this DIF to a (N+1)-DIF or a (N-1)-DIF. The reference model says there may not be an individual task identified as RMT, so from an engineering perspective we could probably put this relaying function at the very beginning of the DTP pipeline. If relaying out-of-process then encode; if not relaying, then skip encoding and just pass the in-memory reference.

I'm not sure if this breaks other guarantees or not. Typically we see the information flow down the pipeline like this: delimiting passes PDUs to EFCP which passes them to RMT and finally passes to SDU Protection. In the delimiting step the PCI has already been added.

It's clear I don't understand this enough. Time to dive in again.

# 20190319
#### Another Eureka?
The delimiting step seemed too _limited_ for what I want to achieve in a dynamic language like Ruby. I want to pass a reference as long as we are still *in process* rather than marshal/encode the damn thing just to pass it to another thread. It seemed like the RMT function was out of place. If I could _just know_ if the message would be passed through the process boundary, I would know to encode it at the delimiting step. But RMT doesn't get invoked until _later_. What to do?

My internal dialog was raging. "This is *not* the service level that I need! I need... duh." Service Level. What controls that? QoS cube. What concept has been hammered into the reader of the Patterns book from the earliest chapters? Separate mechanism from _policy_. 

I need a _policy_ assigned to the delimiter based on parameters in the QoS cube. I needed to expand my thinking beyond the 5 or 6 dimensions of the QoS cube I imagined: jitter, delay, bps, etc. I need a dimension called "zero copy" or similar. 

When the _flow is being established_ I can specify that I need "zero copy" or "reference pass" as part of my QoS. If both ends of the _flow_ terminate within the same process boundary, I can achieve that goal! If one end terminates outside the process, I'll get an error back on that dimension (with a suggested downgrade?).

I'll have to look at the mechanism for associating policies with different aspects of the DIF, but it's clear that I can/should attach an encoding policy to my "zero copy" requirement. Pass a function pointer which itself will take the object-to-be-encoded as an argument and figure out what to do with it. In Ruby that's easy. In C it's also easy.

For the "zero copy" case, the encoding is a no op. For passing the process boundary, it could be as simple as:

```ruby
def encoding_policy(object)
  object.encode
end
```
For C, some casting will be required. I'll have to refamiliarize myself with the right syntax, but psuedo-code it would be:
```C
void* encode(obj_ptr *p) {
  ((some_struct *) p)->encode()
}
```
Anyway, the main take away here is that I can specify a QoS for the _flow_ itself along with an associated policy. I no longer need to wait to the RMT stage to know if the message will pass the process boundary *_because_* the _flow_ establishment confirmed that will be true for the lifetime of the _flow_. The policy is enforced "globally" on this flow.

Second, what's even cooler is that I could establish another flow to an AP outside this process boundary and still potentially get "zero copy" if it's on the same host. This wouldn't work for Ruby but it damn sure would work for passing object pointers in a language like C if the objects were allocated in shared memory. If I establish a flow looking for "zero copy" and the remote end terminates in an AE in another process on the same box, then the policy could allow for reference passing all the way through. This would even work through multiple DIFs all on the same box if they support the "zero copy" QoS. Very cool.

Third, the original AP could have an AE establish a flow to a remote (different host) AP and transparently handle the encoding/decoding of the Ruby object as it moves through the flow. Normally when dealing with BSD sockets you need to provide a raw byte buffer to transmit. With a _flow_, pass the object reference to it and let the policy handle the rest. Could be a reference pass, could be an encoding step (JSON, ProtocolBuffers, netstring, etc), could be a `bcopy` to a newly malloc'ed buffer...

This eureka moment came after I was reading the DelimitingGeneral130904.pdf doc. I despaired at all the discussion about the header layout. It was clear that I needed to know inproc/outproc before this step. In my despair, I found the solution. Didn't take long either... I only wallowed in it for 5m or so until the light bulb went off. :)

#### Quote
"A DAP uses a DIF to send SDUs to other DAP members of the same DAF. Two DAPs in the same DAF must use the same DIF to communicate directly."

I don't know how many times I'll need that drilled into my head. But see below because this quote ignores the degenerate case.

#### Infinite Regress
My approach has been that each thread in a process corresponds to an AE. They are the DAPs in a DAF. Now we see from above that a DAF must use a DIF to communicate. However, the ref model says that a DAF has an IPC Process Management task. It's the job of this task to coordinate with the underlying DIF to facilitate the communication. 

Originally I envisioned a single thread in the AP/DAF that would be designated as the DIF. However, I apparently would then need to push IPC Process Management into each of the AE/DAPs in order to treat that thread as a DIF. Alternately, there would be a DIF thread and a IPCP thread within the same process. I think that's the wrong perspective. Reason is then you have to look at each AE/DAP and apportion some piece to IPC Process Management OR you end up doubling your resource consumption for IPC. Dumb.

Therefore, let's say the AP/DAF has many threads that act as AE/DAPs. A single thread can then be designated as the IPC Process Management Task. It will facilitate communication between the threads. This is the degenerate case; we don't break it down any more granularly than this because it doesn't gain us anything. In this degenerate case, _there is no DIF_ to facilitate the communications so the quote above is wrong.

Once this works within a single AP, then I can extend the problem to manage communication between two APs (both members of same DAF). At this point I will need a (N)-DIF for them to communicate over. Each AP will have its designated IPCP task thread which will pass data to the DIF for delivery to the remote end.

This makes more sense. Another way of looking at this is that an AP/DAF does NOT have an internal DIF. That concept regresses infinitely. But if we say each AP/DAF has a dedicated IPCP thread (or task) then conceptually we can make the quote above come true once there are 2+ DAPs in the DAF. 

#### Enough Theory
Time to put these thoughts into practice tomorrow.
