from asyncio import DatagramProtocol, get_event_loop
from collections import OrderedDict
from logging import getLogger
from socket import (INADDR_ANY, IPPROTO_IP, IP_ADD_MEMBERSHIP,
                    IP_DROP_MEMBERSHIP, inet_aton)
from struct import Struct

from .exceptions import NotConnectedError
from .parse import MESSAGE_DROPPED, Frame, parse, pack_request_message


MAX_CACHE_SIZE = 2 ** 10


async def create_subscribe_socket(local_addr, loop=None, message_callback=None,
                                  protocol_version=1):
    loop = get_event_loop() if loop is None else loop
    log = getLogger(__name__)
    log.debug('creating subscribe socket')
    if protocol_version != 1:
        raise NotImplementedError('protocol versions other than 1 not '
                                  'supported')
    factory = lambda: SubscribeProtocol(loop=loop,
                                        message_callback=message_callback)
    transport, protocol = await loop.create_datagram_endpoint(
        factory, local_addr=local_addr, reuse_address=True
    )

    return protocol


class SubscribeProtocol(DatagramProtocol):
    _igmp_struct = Struct('!4sL')

    def __init__(self, loop=None, timeout=3, message_callback=None):
        self.loop = get_event_loop() if loop is None else loop
        self.log = getLogger(__name__)
        self.transport = None
        self.socket = None
        self.timeout = timeout
        self.message_cb = message_callback
        # structures for consolidating multi-frame messages
        self._incomplete_messages = dict()
        self._missing_frames = dict()
        self._message_timeouts = dict()
        self._complete_messages = OrderedDict()
        self._max_cache_size = MAX_CACHE_SIZE

    def connection_made(self, transport):
        self.transport = transport
        self.socket = self.transport.get_extra_info('socket')

    def connection_lost(self, exc):
        self.transport = None
        self.socket = None

    def datagram_received(self, data, addr):
        frame = parse(data)

        if frame.frame_type == MESSAGE_DROPPED:
            self._clean_up_message(frame.uid)
        elif frame.uid in self._incomplete_messages:
            self._receive_known_message_frame(frame)
        elif frame.uid in self._complete_messages:
            self.log.warning('received duplicate frame from already-complete '
                             'message')
        else:
            self._receive_unknown_message_frame(frame, addr)

    def subscribe(self, address):
        if self.socket is None:
            self.log.error('cannot subscribe: no socket available')
            return

        self._send_igmp(address, IP_ADD_MEMBERSHIP)

    def unsubscribe(self, address):
        if self.socket is None:
            self.log.error('cannot unsubscribe: no socket available')
            return

        self._send_igmp(address, IP_DROP_MEMBERSHIP)

    def close(self):
        if self.transport is not None:
            self.transport.close()

    def _receive_known_message_frame(self, frame: Frame):
        if frame.uid not in self._incomplete_messages:
            self.log.error('cannot update incomplete message: partial message '
                           'not found')
            return

        self._update_incomplete_message(frame)

    def _receive_unknown_message_frame(self, frame: Frame, source_address):
        # if this is a single-frame message, immediately return it
        if frame.frame_number == 0 and frame.total_frames == 1:
            self._complete_message(frame.uid, frame.topic, frame.body)
            return

        self._start_incomplete_message(frame, source_address)

    def _start_incomplete_message(self, frame, source_address):
        # set up the structure to store message frames
        all_frames = [None]*frame.total_frames
        all_frames[frame.frame_number] = frame
        self._incomplete_messages[frame.uid] = all_frames

        # record which frames are missing and set up a timeout to ask for the
        # missing frames to be resent
        remaining_frames = set(range(frame.total_frames))
        remaining_frames.remove(frame.frame_number)
        self._missing_frames[frame.uid] = remaining_frames

        check_time = self.loop.time() + self.timeout
        self._message_timeouts[frame.uid] = check_time
        self.loop.call_at(check_time, self._ensure_message, source_address,
                          frame.uid, frame.total_frames)

    def _update_incomplete_message(self, frame: Frame):
        self._incomplete_messages[frame.uid][frame.frame_number] = frame
        self._missing_frames[frame.uid].remove(frame.frame_number)

        # if this was the last frame, complete the message
        if not self._missing_frames[frame.uid]:
            all_frames = self._incomplete_messages[frame.uid]
            topic = all_frames[0].topic
            body = b''.join([f.body for f in all_frames])
            self._complete_message(frame.uid, topic, body)
        else:
            # not the last frame, so update the timeout that triggers
            # requesting missing frames
            self._message_timeouts[frame.uid] = self.loop.time() + self.timeout

    def _complete_message(self, uid, topic, message_body):
        # clean up multi-framing structures
        self._clean_up_message(uid)

        # cache the complete message's UID to ignore duplicate frames that
        # may have been slowed on the network
        self._complete_messages[uid] = None
        while len(self._complete_messages) > self._max_cache_size:
            self._complete_messages.popitem(last=False)

        # call the callback with the topic and message contents
        self.message_cb(topic, message_body)

    def _clean_up_message(self, uid):
        if uid in self._incomplete_messages:
            self._incomplete_messages.pop(uid)
        if uid in self._missing_frames:
            self._missing_frames.pop(uid)
        if uid in self._message_timeouts:
            self._message_timeouts.pop(uid)

    def _ensure_message(self, source_address, uid, total_frames):
        # if the message is complete we're done
        if uid not in self._message_timeouts:
            return

        # if the call time has been updated, call again later
        if self.loop.time() < self._message_timeouts[uid]:
            when = self._message_timeouts[uid]
        else:
            # timeout triggered: request missing messages and wait again
            self.log.debug('timed out waiting for frames for message %s',
                           hex(uid))
            self._request_missing_frames(source_address, uid, total_frames,
                                         *self._missing_frames[uid])
            when = self.loop.time() + self.timeout

        self.loop.call_at(when, self._ensure_message, source_address, uid,
                          total_frames)

    def _request_missing_frames(self, address, uid, total_frames,
                                *frame_numbers):
        if self.transport is None:
            raise NotConnectedError

        self.log.debug('requesting missing frames %s for message %s',
                       frame_numbers, hex(uid))
        for frame_number in frame_numbers:
            request = pack_request_message(uid, frame_number, total_frames)
            self.transport.sendto(request, address)

    def _send_igmp(self, address: str, request_type: int):
        group = inet_aton(address)
        mreq = self._igmp_struct.pack(group, INADDR_ANY)
        self.socket.setsockopt(IPPROTO_IP, request_type, mreq)
