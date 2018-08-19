# umps
**UDP Multicast Publish-Subscribe** is a publish-subscribe group
communication system based on IP multicast.
It is designed to be an extremely lightweight, scalable messaging system for
use in private (home or corporate) networks.

### Broker-less Subscription Management
Instead of using a broker application to manage subscriptions and distribute
messages (*application layer* multicast), UMPS uses IP multicast to leverage
existing network hardware for the distribution of messages (*network layer* 
multicast).

This bypasses the challenges of scale of brokered publish-subscribe systems,
where the broker application becomes a bottleneck, at the cost of slightly
less reliable message delivery.

### Messaging Limitations and Loss Detection
UDP is an inherently unreliable and limited protocol.
There is no built-in mechanism for subscribers to know if a message has been
dropped, and routers only support messages up to a certain size before they are
broken up into smaller chunks.  If any one of the chunks is lost, the entire
message is dropped, exacerbating the loss problem.

UMPS supports *message framing* and frame retransmission. Publishers break up
large messages into smaller *frames* that are transmitted individually.
Subscribers reconstruct the entire message before providing it to the
application.
If a subscriber detects that it is missing a frame, it can request that 
frame be retransmitted specifically to it.

Message caching handles the low-hanging fruit of intermittent, single-frame
loss, but it can't guarantee every message will reach every subscriber under
continuous high network load.
For this reason, UMPS is intended for private or corporate use, not for
extremely large-scale use over the open internet, where continuous heavy load
is much more likely.