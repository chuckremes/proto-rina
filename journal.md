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


# 20190320
#### Naming Note
A whatevercast name is a name of a set.

#### Quote
"Or more precisely, there is not much point in trying to draw a fine line between the DAF IPC Management components and DIF components, such as Resource Allocation, etc. They can and should meld into each other. In other words, it is pointless to try to distinguish too rigidly between DAF IPC management and the broader DIF IPC Management associated with DIFs. What is important is the subset that is available for DAF support alone. That should be limited to coordination required for DAF members. The only coordination among DAF members should be for IDD updates. Any coordination beyond that should be a DIF."

I don't know what IDD means in this or any context. But the quote above gives me hope that I'm not straying too far afield.

#### Quote
"When IPC Management receives an Allocate Request for IPC resources, if the IRM fails to find the requested application supported by any of the DIFs available to it, it will consult the DIF Allocator to find a DIF that does support the requested application."

Interesting. This implies that a DIF Allocator can know about DIFs (or can find DIFs) that its own DIF doesn't know. Not quite sure what to make of this or how it would work. Probably more of those "evil" well-known ports.

#### Startup
After name registration, we need a way for the threads to indicate they want to create a flow between them. We should probably have some threads defined as flow listeners and others as flow connectors. The threads should be configured to know which *services* they want to get (not necessarily a specific thread name!) and let the IPCP handle matching them up.

In my example case, I'm planning to have a `JokeServer` which listens for requests to tell jokes, and a `JokeClient` which seeks out a JokeServer and asks it for jokes. No "well known" ports here, just names. Let the IPCP manage the allocation as the ref model defines. I'm thinking each thread will register its name (e.g. JokeClient, JokeServer) but the service name will be "joke teller". So "joke teller" will be a synonym for this specific JokeServer.

The authentication/CACE should be a null op here for simplicity. But the threads will still need to go through the connect-request -> connect-response -> establishment dance. Once working, we can experiment with more interesting authentication protocols.

I'll be interested to see what the in-process QoS cube looks like. Guess I get to define it.

#### DAF Enrollment Again
This section (3.3.6) comes after the discussion about Application Connection Establishment.

"For an application process to join a DAF, it must be enrolled. Enrollment is carried out by the DAF Management task of the DAF infrastructure. Enrollment begins with an application process establishing an application connection with a member of the DAF. Once this management connection is created and the new member has been authenticated, the new DAP must be initialized."

Not sure here... perhaps each thread (a DAP in the parlance) needs to establish a connection/flow with the IPCP? And this flow is separate from the flow the threads will want to establish between each other? Ugh... these terms are so similar and the boundaries so vague; hard to keep it straight. Or maybe... in this simple case the Enrollment is indistinguishable from a normal Application Connection Establishment. We aren't setting up any distributed RIB synchronization, downloading code, etc. Maybe they are all no ops in this simple case. I'm going with that for now.

Mmm, perhaps this is another eureka moment. I think _enrollment_ means that the IPCP needs to establish itself with the larger DAF/DIF to join it. That is, the IPCP is contacting and enrolling with an IPCP in another DIF/DAF. In our case, we are all in-process so this is a degenerate case (to avoid infinite regress!). Since each thread/AE/DAP _does not_ have its own IPCP then no enrollment occurs. Phew! I am pretty sure this is correct.


# 20190321
#### Housekeeping
My collaborator and friend Donovan Keme has been watching this space closely. He made a wonderful suggestion which is to extract certain elements or bits of wisdom from this journal to its own document. Asking someone to wade through this doc with all of its fits-and-starts, blind alleys, and plain old _wrong conclusions_ is probably a bit much. But if I can distill the lessons learned down to a separate document then I can keep rubber-ducking here while also separating the wheat from the chaff.

I'll do that soon.

Next, Donovan has a nice web hook all setup on his slack channel. It would be convenient if my commits popped up in a channel there both to serve as notice of progress and to allow interested parties to have a one-stop shop for getting the latest news. I'll look into what this takes (API token?) and get it setup for him.

Lastly, he seems to think doing this work on a train is cool. I wish. :)


# 20190322
#### Enrollment
The Patterns book page 260 confirms what I said on 20190320. Enrollment happens when an IPCP uses a (N-1)-DIF to establish an application connection with another IPCP in a (N)-DIF to join it.

Since my initial MVP is going to be all in a single process, there is no (N-1)-DIF nor is there a second IPCP to contact.

However, that raises an interesting thought. To simplify debugging, there's no reason my "second phase" goal couldn't be to create two (N)-DIFs and a single (N-1)-DIF in one process just to see how all of this enrollment stuff will play out. In my view I would have originally targeted using 2 processes to do this via shared memory but this goal is probably even simpler. I don't want to get too far ahead of myself so this will remain in the TODO stage.

#### Registration
The book and ref model never really _directly_ address the topic of AP registration on a host. There's a bit of hand waving and probably some nod towards the text not being an implementation guide.

As noted on 20190306, there needs to be some kind of omniscient/global registration mechanism on a host that knows all APs and DAFs. Why? A few reasons.

1. For the DIF Allocator to work, it needs to be able to find some DIF that supports a currently unknown application name. See note on 20190320. What I believe this means in practice is that there might be two DAFs of same rank that have no (N-m)-DAF in common to connect them. Therefore, the DIF-Allocator can come into play to create a (N+1)-DAF that _spans the scope_ of both (N)-DAFs so they can be connected. As noted sometime before, it's a bit mind bending to realize that sometimes a DAF _goes up the stack_ to relay to another DAF. Regardless, this omniscient registration mechanism knows about both (N)-DAFs and can tell the DIF-Allocator that, hey, DAF-A0 wants to talk to "app-z" but only DAF-B0 has access to it. Then the DIF-Allocator can potentially create a DAF-A1 that spans DAF-A0 and DAF-B0.
2. For any DAF name lookup to work at all, there has to be a way to "seed" the local registration mechanism with entries. Perhaps this is a static list like a YAML file that lists name, purpose, filepath, and some other details which is read into memory when this registration mechanism is bootstrapped at OS bootup. Or, maybe the process happens in reverse where there is a static YAML file that defines this host's DAFs for some mechanism to bootstrap them. When they boot, they register themselves and their known applications (listed in that YAML file) with the registration mechanism. More than one way to skin this cat, I suppose. Maybe it's a combo of the above.
3. I don't have a third reason right now. :)


# 20190325
#### IAP (IPC Access Protocol)
I was looking forward to implementing IAP but I see that it isn't necessary when all lookups occur within a single memory space. There is no "forwarding" of the lookup request to other DAFs in this degenerate case. When I move to the multi-DIF model, this will be a fun exercise. I expect it will require a majority of the DIF internals to work to support the forwarding of requests and the return of a response.

#### Accept Loop
In traditional sockets, the program explicitly binds to a port (not port-id) and listens on it. After listening, it blocks on an `accept` call so that incoming connections can be split off to their port-id for the duration of the connection.

I have a `JokeServer` and a `JokeClient` that I'm building piece-meal. I just got to the point where it makes sense for the `JokeServer` to `listen` for and `accept` incoming requests. And I got stuck for a moment. What should be the correct behavior here for RINA?

From the text and ref model we know that a DIF has the "power" to locate a service and instantiate it if it's not running. That's a really powerful concept that contained nuances I never explored until now. In effect, the DIF is doing the equivalent of the `listen` and `accept` on behalf of any service.

One, it may instantiate a new instance to service an incoming request. Or two, it may hand off the request to an already running instance for it to process.

Let's look at both separately.

1. Instantiate
   This is the interesting one to me since it's new to me (though maybe `systemd` and other modern daemons do this work now... I don't know). What information does the DIF need in order to properly instantiate a process? And how does it get that information?
   
   I believe this is all tied in to the name lookup service. Some mechanism will start RINA (if it hasn't been yet) and register itself with it. It will give the name service its own name (which doubles as the service name that others may connect to), a reference to itself so the DIF can instantiate it, and perhaps some instructions on what arguments may be passed during instantiation. This third bit has me scratching my head a bit. I'd argue that _at most_ it should allow a configuration file to be passed via some convention. Beyond that, the service itself shouldn't need anything to boot or it can have a path to its configuration file statically saved. Hmmm, now that I write that last bit the "statically saved" portion jumps out at me as a bad idea. So, we're back to the first item which is that a configuration file may be passed to the new process.
   
   Since this work is all going on in a single process, we can't exactly `exec` a new process here. We need to start a thread within the process so the service may run at least once and do its work.
   
2. Bind to Running Process
   This is the approach we are all already familiar with. The running process has an ongoing `listen` and `accept` loop running so new requests can be handled faster. We avoid the overhead of instantiation and can just get right to handling the incoming request. 
   
   Maybe the process will handle some number of incoming requests or wait some period between requests and then shut itself down. Ideally RINA could handle the situation where it can't hand off to a running process because it shut down (died, shut down cleanly, doesn't matter). This is interesting to me too. Need to figure out how RINA can tell the difference or that it's reference to a running service has gone dead.
   
   Note I'm saying RINA here instead of DIF. Not sure what owns this responsibility in the DIF yet. Need to review the spec.
   
   What would this handoff to a running process look like? What is the process doing? Presumably it's blocked on something waiting for activity. What is it blocked on? And when there is activity, what does it do next?
   
   In a socket application, the bound socket is (usually) blocked on `accept`. When a new connection comes in to the connection queue, the oldest is popped off and its file descriptor is passed back by reference in the `accept` call. That socket FD can now be used to read/write/close.
   
   In a RINA situation, we could mimic this behavior. Let's say the RINA process is blocked on a flow `read` where the flow handles only incoming requests from the DIF. A message, conforming to a conventional agreed upon protocol, arrives containing the port-id and name of the remote end. This information can be parsed out from the flow and either handled in an event loop or handed off to a thread to process the incoming data. The incoming data in this case would be a `Allocate_Request.deliver` (see D-Base-2011-015.pdf for the narrative). This is all `FlowAllocator` and `FlowAllocatorInstance` work here. None of the narratives really suggest what the destination process is doing, so that's the part I'm making up (i.e. blocked on a read to a "request" flow). This would probably be wrapped up in an API that I could cleverly call `accept`.
   
Interesting stuff that I've run down today. I went from worrying about the name service to diving headlong into the FlowAllocator. Out of time now but I'll code something up on the morning ride.


# 20190326
#### Binding to Accept
So I want to go with a modification of Option 2 from the 20190325 entry. My server class will register itself *and* it will bootstrap itself and wait for incoming flow requests. This seems like it will be a common pattern, so I'd rather do something useful and easy than work on the hardest case first ("booting" a non-running class and handing it a flow request).

Steps appear to be:
1. Register name and self with name service
2. Boot the class
3. Make a (blocking?) method call on the RINA API to read incoming flow requests
4. When a request arrives, handle the request by accepting or rejecting it
5. If accepted the flow, tell a joke to that flow
6. Deallocate the previously accepted flow
7. Go back to waiting for another request

Somewhere in here there will be QoS settings, blocking on read FDs (or the internal equivalent), maybe spawning a new thread to handle the incoming flow, yada yada.

I have Step 1 done. Step 2 will take some thinking because Step 2 is pointless without Step 3. I don't want my initializer to go into an endless loop so there needs to be a separate call to `run` or similar. Details.

In order to do Step 3, I need a `FlowAllocator` and some idea on how to make a `FlowAllocatorInstance`. Flow control is important (a flow is pathological without it!) so we'll need some kind of DTP/DTCP setup too. Lots of code to get Step 3 going. Let's get started.

#### For Those Following Along
When code is pushed, read it with the following in mind:
1. Make it work
2. Make it right
3. Make it fast

I'm actually on Step 0 which is `figure out how to get to Step 1`.


# 20190329
#### DIF Allocator
Ref model section 4.1.6.2:
    The components of the DA-DAF are much as they are in the NSM. The IRM of most applications 
    will only be able to request a new DIF from the DIF-Allocator and have a DIF created for 
    their use. In most cases, the Distributed Management System (DMS) responsible for the 
    domain in which Applications exist will perform all registration related functions. The 
    registration process makes the names of applications and their supporting DIFs along 
    with various properties available to the DA- DAF.


# 20190402
#### Name Search Security
Ref model section 4.1.6.3
    This also ensures that the security of the application is not compromised, by returning 
    whether or not the application exists. If the requesting application’s credentials 
    do not allow access, “not found” is returned.

Interesting stuff on the "null" or "bootstrap" case in that same section towards the end. The enrollment procedure always bothers me because it requires some kind of back-and-forth handshake. Thinking ahead to scenarios where there is a large RTT (or BDP), the default situation should be to send a data PDU that includes the handshake/enrollment information in it. I'll have to dig through the docs again to find what this is called but I know I've seen it. Instead of requiring a response to be returned during enrollment, sufficient information is provided in the first PDU to confirm the enrollment. For example, this would be useful when building intra-solar RINA networks. If it takes hours for a PDU to arrive, you certainly don't want to go through a complex bidirectional handshake to setup the flow!

I can't help but think this bootstrap case provides a broad hint to me on how to bootstrap a system. The DIF-Allocator is clearly an important component but it's complex enough that I don't see an easy way to create even a simple version of it.

Take the example above of bootstrapping a DIF on multi-access media which would be a common case. Some system must generate a PDU to begin enrollment without even knowing who is available in that broadcast domain. This "first broadcaster" sends the PDU with their address (e.g. the MAC) as the "source application" name. The receivers of this broadcast consider their own unique MAC address to be the "destination application name" in this context. I imagine when enrolling in an ethernet configuration, every device will need to broadcast their desire to enroll when they activate. All receivers of this will then enroll that new endpoint into their DIF.

We have the issue of who goes first. Let's break it down into some simple cases:

1. Single device
The degenerate case here is when a multi-access media device activates and broadcasts its desire to enroll in a DIF but receives no response. Given some timeout on the enrollment, I'd think that the local DIF-Allocator would tell the device to create its own IPCP and consider itself a sole-member DIF.

2. Many devices, slow responses
Same as 1, many devices could broadcast their desire to enroll but their timers expire before responses arrive. Every device would then create its own DIF. Ultimately an enrollment would arrive from these other devices and the handshake could commence. However, since each device already generated their own DIF, the DIF-Allocator would need to broker the creation of a (N+1)-DIF to span the multi-access media.

3. Many devices, fast responses
Upon activation, each device broadcasts enrollment. Prior to timer expiration, each device receives another enrollment request. Not sure here, but since each device is broadcasting their desire to enroll in an existing DIF, the fact of enrollment implies there is already a locally running IPCP (that's the only process that can request enrollment) so there is *already a local DIF running*. So this is really Scenario 2.

Lesson learned here is that in order for a device to enroll, it must already have a local DIF even if its the sole member.

The DIF-Allocator has a choice though. In Scenario 2 I said it would broker creation of a (N+1)-DIF to span all nodes but that isn't necessarily true. Each device's DIF-Allocator could agree to merge their DIF with their fellow DIFs.

#### Wireless
The wireless multi-access media interests me now that I'm thinking about this. Our current typical usage is that we see a SSID broadcast by a base station. We try to join it in the clear or with a password. That's enrollment.

However, the interesting part is that we see the SSID broadcast. How would this work in a RINA world? If we take our cue from the IP world, the SSID is broadcast for any nearby listeners to receive. They can choose to enroll or not. But in a RINA world, we do not broadcast our services like that.

I imagine we would fall back on the concept of "well known ports." When given an environment where we don't have any previous information, the IPCP/DIF on our wireless card can try to enroll in the base station's DIF by broadcasting an enrollment request (to a well known port). If we don't have a password yet, we'll be rejected but we will probably be able to figure out the service name that rejected us. That could be the equivalent of the SSID.

I guess this is the same situation as wired multi-access media. I shouldn't let the lack of wires throw me off!

Alternately, maybe all DIFs have a well known port open for one-off queries that don't require enrollment. We could ask the well known DIF port for a list of services and it could reply with the equivalent of the SSID.

Perhaps I'll ask on the mailing list which of these is more in tune with the ref model.


# 20190403
#### Diagram of IPCP

    AE-i ----
             |                       <---
             Port (w/Port-id)            |
             |                           | - flow-allocator-instance-id == port-id
             CEP (w/CEP-Id)              | - CEP-id == EFC-PM-instance-id
             |   EFCPM                   |
             |   (DTT & DCT)             | - state vector stored in RIB
             |                       <---   (CEP + EFCPM deallocate/expire after 2MPL)
             RMT
             |
             SDU Protection
             |
    ------ (N-1)-DIF -------
    
       (mirror image of the above exists at other end of flow)

Several interesting aspects of decoupling the port-id from the cep-id. If traffic stops flowing, we deallocate the cep-id and its state vector for the EFC-PM because the state has expired. However, the port-id (flow-allocator-instance-id) remains in place. If new traffic originates at either end, a new EFC-PM instance is allocated (plus state vector) and it handles passing the traffic through the other IPCP tasks.

For one, this has powerful security implications. One type of attack is a replay attack where a sequence-id wraps around (overflows) and the attacker can use that to perform a man-in-the-middle or other similar attack. RINA avoids this by detecting the sequence-id is about to overflow and _allocates a new cep-id_. Since the total sequence value includes the cep-id, this thwarts the replay attack. And it isn't even a special case! The layer must be able to deallocate and reallocate cep-ids for a flow regularly, so it's just a common operation.


# 20190404
#### Attacks
I don't even know why I'm thinking about this now. When reviewing how _flows_ are created and the connections between their EFCPM-instances, I was once again reminded that the connection is dropped when there is no traffic for 2MPL (Max Packet Lifetime). It occurred to me that an attacker could perform an "EFCPM-instance allocation DoS" by waiting just over 2MPL and then sending traffic again. There's obviously some bookkeeping involved with allocating/deallocating these instances plus the state vector (transmission control block!) that is stored in the RIB.

However, I remind myself that no one can join a DIF without enrolling. If they enrolled, then someone respects their credentials and they are a valid user. If a DAP using an enrolled DIF exhibits this behavior then it isn't really a DoS. _Someone let them in the front door!_ The real solution is to revoke their creds and kick them out. There might be other attack vectors in the enrollment process but that can be mitigated separately.

#### Flow Creation within a DIF
Most of the time I am thinking about flows, it's between two AE/DAPs. However, tasks internal to a DIF can also allocate flows. For example, the RMT (Relaying Multiplexing Task) may have flows with multiple (N-1)-DIFs.

This feels weird because the RMT itself is part of the "pipeline" from an AE flow to the remote end. How can it itself have a flow when it's part of a flow pipeline? I think the answer here is in the "M" part of RMT. Ultimately _N_ flows in a DIF need to relay through (in the common situation) a single (N-1)-DIF. It makes no sense from a resource standpoint to match those _M_ flows to the subordinate layer. Instead, those _M_ flows are multiplexed down to _N_ flows (where N < M) based on QoS characteristics. Flows that need ordered, reliable delivery get multiplexed onto the ordered-reliable-flow. Flows that are best effort, out of order delivery multiplex onto the best-effort-unordered-flow.

I'd guess that the _N_ flows between DIFs will be far smaller than the _M_ flows utilizing that top layer, but that's just conjecture.

Anyway, thinking about the RMT having its own flow means that it has its own EFCPM-instance to manage DTP and DTC. But those EFCPM-i's must be able to skip the RMT otherwise infinite regress.

I should ask on the mailing list about that. I should draw this out on paper too.


# 20190405
#### More on RMT
Thought about it some more and came up with a different perspective. _All_ flows go through the RMT. The RMT looks at their destination application name, consults its forwarding table, and if there's a match it does two things:
1. Adds the Relay PCI to the PDU
2. Matches the source flow's QoS to one of its flows to the (N-1)-DIF. If matched, it hands the PDU to that flow, otherwise it creates a new flow with the appropriate QoS to the (N-1)-DIF.

If the forwarding table produces no match, then I think we conclude it's a local delivery and the Relay PCI is _not added_. Where does the PDU go and how does it get there?

I _think_ the PDU is just directly added to the incoming queue for the local destination connection-endpoint. We skip the SDU Protection step since the PDU is not leaving the DIF at all. The incoming queue would be hooked up to the "remote" end's EFCPM-instance which would unwrap the PDU and deliver it to the AE on the next _read_ API call. I'd bet there are some further steps related to QoS like dropping the PDU if the queue is full and it's best-effort or something. Perhaps flow-control or congestion-control kick in for that case (yes, locally).

Let's back up and look more closely at what the RMT does for a *match* that is relayed to the (N-1)-DIF. The reference model says the PDU is multiplexed onto the appropriate flow (creating one if it doesn't exist), but then there's a "hand wave" and suddenly the PDU goes through SDU Protection step and is written to the (N-1)-DIF. I say it's a "hand wave" because some important details are left out that I'm not sure how to handle.

If the RMT has a _flow_ to the (N-1)-DIF, then it should have all the same supporting structure as any other flow. But that leads to infinite regress because that supporting structure would include another RMT. So let's assume that this is some kind of degenerate case of a flow that makes the RMT a no op. The PDU would still need to go through the delimiting step, EFCPM-i handling, RMT no op, and then SDU Protection (again?). Hmmm, so I think we must assume the Delimiting step here is also a no op. Although it might be that the multiplexing operation has to do some work which is effectively delimiting anyway.

Let's explore that for a moment. It's feasible that the upstream flow has a max PDU size either smaller or larger than the RMT flow to the (N-1)-DIF. If upstream's is smaller, then the RMT can potentially add multiple PDUs to its PDU before sending. If upstream's is larger, then the RMT may need to fragment the PDU and do multiple writes to its flow. Using the RMT flow as a new frame of reference, the upstream flow's PDU is _this stream's_ SDU. SDUs always go through delimiting. Both cases appear to need some kind of delimiting, so it is _not_ a no op.

Back to the RMT flow pipeline. We've established it has its own delimiting step. It must also have its own EFCPM-instance for handling flow-control to the lower DIF. The RMT step in this pipeline is absolutely a no op. And lastly, the SDU Protection step must occur. I believe this step "belongs to" the upstream flow, so the RMT flow's SDU Protection is effectively a no op but the PDU immediately filters through the upstream flow's SDU Protection step. Maybe it doesn't matter which flow we say "owns" that SDU Protection. I'll need to revisit the docs and see if SDU Protection is the same DIF-wide or if it's per flow. It really only makes sense for it to be "global" to the DIF so the remote end knows how to decode it. Yeah, it's DIF-wide and not per flow.

I'll also revisit my earlier remark about which flow _owns_ the SDU Protection step and I'll say it's the RMT that owns it. Reason is that if the PDU is delivered locally, we'll never put it through SDU Protection; it will be delivered directly. So therefore, SDU Protection is only necessary when leaving the DIF and is the proper responsibility of the RMT flows.

Let's try and draw it.

    RMT -------------
              |
              |
            Check forwarding table
                      |
                    /   \
                  /       \
              No match      -------- match! -------
                 |                                 |
              Deliver locally                      |
                                               Map/write to correct (N-1)-DIF flow
                                                   |
                                                Delimiting
                                                   |
                                                EFCPM-i
                                                   |
                                                RMT (no op)
                                                   |
                                                SDU Protection
                                                   |
                                                ???????

Not quite sure what happens at that last step. We have written to the appropriate RMT flow but what does that mean really? How does the hand-off to the (N-1)-DIF occur? Need to think on this. It's probably obvious but I can't see it right now.


# 20190411
#### RMT Hand-Off to (N-1)-DIF
Had a terrible sickness for last few days; food poisoning. Ugh.

Anyway, the distance of time hasn't offered me any solution to the last question asked about RMT hand-off. So, let's rubber duck this thing.

How does it work in IP today? Well, it's been 20 years (!) since I wrote an ethernet driver (tulip chipsets) but my recollection was that I had to setup a memory segment in main memory that the card had permission to DMA (direct memory access) over the bus. There was a buffer of some kind (ring buffer?) and I had to provide a memory address to its start along with a list length. When the system had added mbufs to the list, it made a call into my driver that then twiddled a bit (or set of bits) on the card to enable transmission. I _think_ the card would then read the memory address which was essentially pointing to an mbuf header and then figure out how much data was there to copy from memory and send over the wire.

So how might this apply to RINA? The RMT flow to the (N-1)-DIF has both an outgoing and incoming queue, presumably. When all RINA steps have been taken, the PDU is placed on the outgoing queue. And then...

Here's a gap. The ref model is silent on this topic probably because it's an implementation detail. :)

And the main API that the ref model discusses is the API used by AEs to talk to a DIF/IPCP. That's the open, close, read, write, stop, start set of primitives I think. Hmmm, maybe not. I think that might refer to the 6 basic operations that are part of any protocol. Double hmmm... actually the API I'm concerned with is the allocate_request, allocate_response, send, receive, deallocate operations.

Hold the phone! From the perspective of the (N-1)-DIF, the N-DIF is essentially an AE. So it presents the same API to the N-DIF that it would to any AE which is that same list of operations: allocate_request, allocate_response, send, receive, deallocate.

So the RMT flow was _allocated_ to the (N-1)-DIF upon _enrollment_. That means the RMT can send/receive on the flow. But now we're back to (almost) square one where the outgoing PDU is placed on an outbound queue. Then what???


# 20190415
#### Book Prose vs Ref Model
I find myself increasingly referring back to the book. I find it to be much better written and clearer about concepts than the reference model documentation. I wonder if the medium is influencing me? Do I prefer paper and ink over light and pixels for comprehension?

#### API Service Primitives
Finally clarified this for myself. When an AP wants to open a flow to another AP, it invokes the IPC Service primitives which are:
 * Allocate Request
 * Allocate Response
 * Send
 * Receive
 * Deallocate

The calls to _Send_ and _Receive_ are data transfer API primitives. These send/receive SDUs on an established flow. See pages 268+ for a narrative on how data transfer occurs between APs. Most enlightening on this umpteenth reread.


# 20190417
#### Update
Been reading and thinking.

Confirmed some inconsistencies between the book and ref model regarding RMT. In book, it handles outbound messages prior to the SDU Protection step and prepends PCI (page 255). "All PDUs for all EFCP connections have Relaying PCI prepended to the PDUs. This Relaying PCI is associated with the relaying and multiplexing function. When a DIF has more than two IPC processes (i.e. most of the time), this task must also add addressing information to the PCI. The PCI contains the source and destination addresses." Then on page 257, "The last function performed on PDUs before they are delivered to the layer below is taking necessary precautions to safeguard their integrity. Any data corruption protection over the data _and PCI_, including lifetime guards and/or encryption, are performed here."

In ref model, it may modify PCI but doesn't add any (section 5.1.4.4), plus it's called _after_ SDU Protection. "Actual systems may well be various combinations of these. The RMT does not generate any additional PCI."

"5.1.4.5. SDU Protection
SDU Protection has the same functionality as described as part of IPC Management in the common DAP infrastructure. The only slight difference here is that an IPC Process may have more than one supporting DIF. The SDU Protection on each (N-1)-flow may be different. This will primarily occur where the (N-1)-DIF must reflect the limited characteristics of the media." This is the key element. If there are multiple flows to different (N-1)-DIFs each with their own SDU protection policy, the RMT _must be invoked first_ to assign a PDU to one of those flows. It's the only function that can handle this assignment so it must run first, and _then the SDU protection_ may run.

PNA Technical Note #DIF-DT-6 (D-Base-2012-010.pdf) in the introduction section says: "This task generates no protocol, but may modify PCI of PDUs it processes." Then in Section 5.2 it says, "PDUs are delivered to the RMT ready to be forwarded. No further processing is required. For outgoing PDUs, this implies SDU Protection has already been applied."

I have issues with this.

#### Facts
* APs (Application Processes) are not part of the DIF (book, page xxxx)
* 


# 20190424
#### Progress?
I've been emailing back and forth with the RINA ML. Some interesting things were said. Ultimately my plans are unchanged. Will continue working on putting a DIF into each AP to facilitate local concurrency operations while allowing for simple growth to a distributed model without any API changes. If it's all message passing, then scaling up and out should be easy.

I spent a lot of time on those emails. I have limited time to think through _and code_ my ideas, so it's time to prioritize that aspect again.

But tomorrow. Too tired today.


# 20190430
#### Process as an OS
Last week there was a flurry of emails to the ML. I proposed my structure of embedding a DIF inside each AP and letting the threads use it for intra-process communication. Lots of pushback from Day. But! We ultimately came to an understanding and it turns out our disagreement was rooted in _definitions_.

When I described the AP as DIF + threads model, he vehemently disagreed. After some back and forth it became clear to me that he and I defined "process" differently. While I was taking the modern day UNIX process view, Day was arguing from some never-seen-in-the-wild perfect model where the "process" was like an operating system unto itself and its threads were APs! That's right, in this situation the threads were APs and the process was something else (still not sure on its name).

So, we were actually in agreement but we had different definitions for these common elements.

I will be pushing forward on embedding a DIF-per-UNIX-process. This time I will define each AP as a thread.


# 20190501
#### Restart Coding
Less blather, more coding.

#### Recap
I have written a small `Registry` function. As threads/APs launch, they can notify the Registration mechanism of their service name. Something tells me they should also register other details. Perhaps a default QoS? I'd imagine we would want inter-AP comms within a process to use the highest level of delivery and side-step any marshal/unmarshal policy; just pass references. However, the QoS could also specify "best effort" wherein messages are dropped if the "remote end" reads too slowly.

With Registration semi-functional, what's next? Remember that APs don't need to enroll in the local DIF, they just use it. Therefore, next step is to have the "server" AP make a call to setup a service flow to handle incoming connections. 

After that, have the "client" AP try to establish a flow with the service name "incoming" flow. Presumably that will entail some minor enrollment procedure (probably just a no op for now) but the allocate request reply should point the requestor to a new address. That is, do not return the address of the "incoming" flow... hmmm, this just tripped a thought.

As far as the client side is concerned, it doesn't need to know the "service incoming" name though it could. It just needs to ask for a flow to that service and the DIF should pass the allocate request to it. This specific server AE then can create a new AE to manage the new flow. Put another way, the server AE has a flow established with the DIF for incoming allocate requests.

I've come full circle. This is what I said to do in the second paragraph above. The main takeaway is that the permanent AE listening for allocate requests never returns its address in the reply. It undertakes to create a new AE and its address should be returned. How does this new AE get an address assigned? Not sure, but clearly that address assignment happens from the DIF. Need to look at the M_CONNECT stuff and see how that narrative describes the procedure.

1. Verify APs are registering a name
2. Server AP to setup a listening flow
3. Client AP to send a allocate request
4. Server AP to create new AE for incoming request, get an address assigned
5. Server AP to send allocate request reply with address embedded
6. Client AP to receive allocate request reply
7. ...


# 20190502
#### Recap Continued
On further reflection, I'm kind of disappointed that we are ending up with the `listen` and `accept` style calls for RINA just like for BSD sockets. I had hoped for something new and interesting. Perhaps it's a failure of my imagination.

This issue of listening for connections and somehow getting a new address assigned had me perplexed. Here's how I think it will work in practice. This is an implementation detail not covered by the book or ref model.

A "server" will open a flow _with the DIF_ probably connecting to a "well known port" like "DIF-listener service." This service will be contacted when _allocate requests_ come through to match up the request with the appropriate service. When a match is found, a message will be sent on that "listen flow" to the AP. The AP will get this message and use its contents to create a new flow with the requestor. This is how the address is assigned by the DIF! Shoot, ran out of time... will continue this thought tonight.

Reread D-Base-2011-015.pdf to get some idea of the submit/deliver process. I think what will happen here is that the "listen flow" will deliver the AllocateRequest.deliver to the AE. If the AE accepts this request, the AE will invoke AllocateResponse (this is effectively the BSD `accept` calls). This will setup the flow binding from the perspective of the destination application. Presumably the DIF will fill in the destination address details in that response PDU and send it back.

The Response PDU makes its way back to the requestor, and the state machine advances as described in the documentation. 

The key difference here is that we have this permanent flow configured between the DIF and the AE to listen for incoming AllocateRequest PDUs. They are delivered to the destination AE. The destination AE may refuse in which case the response with a correct error code will propogate back to the source via the half-configured FAI. If the AE accepts the request, the AE sets up the final FAI endpoint via the call to AllocateResponse. 

I hope that makes sense ^^. 

Will try and lay down some of this code tomorrow morning.
