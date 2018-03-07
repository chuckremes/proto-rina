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

# Who
I'm just a curious guy who wants to see how this can work.

(c) 2018, Chuck Remes.
