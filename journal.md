20190211
This is my first official journal entry. The purpose of the journal is to record ideas on how to engineer and implement RINA. I have been thinking off and on about how to handle this implementation for about a year, but I haven't recorded any of my thoughts. I now find myself having to rediscover ideas and concepts that I had previously thought through. That has annoyed me. Time to write them down.

#### Layer1 / Layer2 hardware
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