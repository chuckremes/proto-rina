# Tutorial

To provide an overview of RINA, the exploration of this alternate stack will occur as a comparison of TCP to RINA. Most readers will be familiar with the dominant networking stack so it makes sense to compare and contrast as a mechanism to teach RINA. 

Not all concepts in TCP are necessarily present in RINA and vice versa. Similarly, there may be concepts in RINA that have no specific analogue in TCP.

## Index

* TCP Overview (30k view)
* TCP Components
  * IP
  * Name resolution
  * Address Assignment
  * Session establishment
  * Session teardown
  * Routing
  * Fragmentation / Reassembly
  * Congestion control
  * Retransmission
* RINA Overview
* RINA Components
  * Default SDU
  * Name Resolution
  * QoS
  * DIF Enrollment
  * DIF Flow Termination
  * PDU Delimiting
  * PDU Multiplexing and Fragmentation
  * Data Transmission

## TCP Overview

Transmission Control Protocol (TCP) is an ordered, reliable data transmission protocol built on top of Internet Protocol (IP). It provides for point-to-point communication between two addresses commonly referred to as IP addresses and denoted as a set of 4 bytes separated by periods (e.g. 192.168.1.3).

The Quality of Service (QoS) allowed by TCP includes 1) ordered delivery, and 2) reliable delivery. In the event of corrupted or missing packets, TCP will retransmit the packets. In the event of out-of-order delivery, TCP will buffer and reorder the packets to the proper sequence before handing them off to the client application.

TCP has no built-in mechanism for disabling these QoS features.

TCP also has no facility for directly providing the following services:

* Data compression
* Encryption
* Service discovery
* Authenticated Session Establishment or Identity Services
* Routing or Packet Forwarding
* Name to Address (or vice versa) Translation
* Dynamic Address Assignment
* Mobility Services

### TCP Components and Add-on Services

TCP is comprised of a few components and external services.

#### Internet Protocol

Briefly discuss packet layout. Explain checksum. Explain fragmentation and reassembly.

#### Address Assignment

Static and DHCP

#### Name Resolution

Local file lookup and DNS

#### Session Establishment

TCP utilizes a three-way handshake to establish a session with a remote process. It's referred to as a three-way handshake due to it requiring 3 packets of information to formally establish the connection.

1. SYN
The first packet transmitted from the source to destination is a syncrhonization (SYN) packet. It contains a randomly generated initial sequence number (for ordering purposes), the maximum allowed packet size, and the maximum buffer size.

2. SYN-ACK
The destination process responds with its own initial sequence number for the returned replies. It also includes the maximum packet size and its maximum buffer size. 

The source and destination ends use the maximum packet size to agree on the standard packet size for this session. It is typically the smaller of the two "maximum packet size" values so that both ends of the connection can avoid the work of packet fragmentation and reassembly.

3. ACK
Finally, the source transmits the final packet of the handshake to acknowledge the sequence number (and increments it by 1). 

At this point, the session has been established and traffic may flow bidirectionally.