from asyncio import DatagramProtocol, get_event_loop
from collections import OrderedDict
from functools import partial
from logging import getLogger
from socket import IPPROTO_IP, IP_MULTICAST_TTL
from typing import Tuple
from uuid import uuid4

from .exceptions import NotConnectedError
from .parse import (FRAME_REQUEST, parse, pack, pack_drop_message,
                    set_response_frame_type)


async def create_publish_socket(local_addr, loop=None, max_cache_size=None,
                                time_to_live=None):
    loop = get_event_loop() if loop is None else loop
    log = getLogger(__name__)
    log.debug('creating publish socket')
    factory = partial(PublishProtocol, loop=loop, max_cache_size=max_cache_size,
                      time_to_live=time_to_live)
    transport, protocol = await loop.create_datagram_endpoint(
        factory, local_addr=local_addr, reuse_address=True
    )

    return protocol


class PublishProtocol(DatagramProtocol):
    def __init__(self, loop=None, max_cache_size=None, time_to_live=None):
        self.loop = get_event_loop() if loop is None else loop
        self.log = getLogger(__name__)
        self.transport = None
        self._message_cache = OrderedDict()
        self._max_cache_size = 20 if max_cache_size is None else max_cache_size
        self._ttl = 3 if time_to_live is None else time_to_live

    def connection_made(self, transport):
        self.log.debug('connection made: %s (local) to %s (remote)',
                       transport.get_extra_info('sockname'),
                       transport.get_extra_info('peername'))
        self.transport = transport
        sock = self.transport.get_extra_info('socket')
        sock.setsockopt(IPPROTO_IP, IP_MULTICAST_TTL, self._ttl)

    def connection_lost(self, exc):
        if exc:
            self.log.warning('connection lost')
        else:
            self.log.debug('connection closed')
        self.transport = None

    def datagram_received(self, data, addr):
        self.log.debug('frame received from %s', addr)
        frame = parse(data)

        if frame.frame_type != FRAME_REQUEST:
            self.log.warning('received frame is not a request frame; ignoring '
                             'frame')
            return

        if frame.uid in self._message_cache:
            # find the requested frame and send it
            self.log.debug('frame of cached message found')
            frame = self._message_cache[frame.uid][frame.frame_number]
        else:
            # send a response that the message is no longer cached
            self.log.debug('message no longer cached; creating drop-message '
                           'frame')
            frame = pack_drop_message(frame.uid, frame.frame_number,
                                      frame.total_frames)

        self.transport.sendto(frame, addr)

    def publish(self, destination, topic: str, message: bytes):
        if self.transport is None:
            raise NotConnectedError

        uid = generate_uid()
        frames = pack(uid, topic, message)
        for frame in frames:
            self.transport.sendto(frame, destination)

        set_response_frame_type(*frames)
        self._cache_message(uid, frames)

    def close(self):
        if self.transport is not None:
            self.transport.close()

    def _cache_message(self, uid: int, frames: Tuple[bytearray]):
        self._message_cache[uid] = frames
        while len(self._message_cache) > self._max_cache_size:
            self._message_cache.popitem(last=False)


def generate_uid():
    return int(uuid4()) >> 64
