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
