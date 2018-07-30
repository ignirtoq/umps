from collections import namedtuple
from math import ceil
from struct import Struct, unpack_from
from typing import Tuple, Union


_header = Struct('!HBQ2B')
_topic_size = Struct('!B')
MAX_UDP_SIZE = 512  # bytes
MAX_BODY_SIZE = MAX_UDP_SIZE - _header.size

PROTOCOL_VERSION_UPPER = 0x1 << 4

VERSION_TYPE_BYTE_POSITION = 2

# v1 message types
TYPE_MASK = 0xF
START_FRAME = 0x1
CONTINUATION_FRAME = 0x2
FRAME_REQUEST = 0x3
FRAME_RESPONSE = 0x4
MESSAGE_DROPPED = 0x5

Frame = namedtuple('Frame', ['size', 'protocol_version', 'frame_type', 'uid',
                             'frame_number', 'total_frames', 'topic', 'body'])


def parse(frame_bytes: Union[bytes, bytearray]) -> Frame:
    size, vt, uid, frame, total_frames = _header.unpack_from(frame_bytes, 0)
    protocol_version = vt >> 4
    frame_type = TYPE_MASK & vt
    body_start = _header.size
    if frame_type == START_FRAME:
        topic_size, = _topic_size.unpack_from(frame_bytes, _header.size)
        topic_bytes = unpack_from('!%ds' % topic_size, frame_bytes,
                                  _header.size + _topic_size.size)[0]
        topic = topic_bytes.decode('utf-8')
        body_start += 1 + topic_size
    else:
        topic = None

    return Frame(size, protocol_version, frame_type, uid, frame,
                 total_frames, topic, frame_bytes[body_start:])


def pack(uid: int, topic: str, body: Union[bytes, str]) -> Tuple[bytearray]:
    topic = topic.encode('utf-8')
    if isinstance(body, str):
        body = body.encode('utf-8')

    # compute the total number of frames we need to multicast the message,
    # keeping each frame under the fragmentation limit for UDP
    body_size = len(body)
    # we'll have at least one frame, but the first frame also contains the
    # topic, so it can't hold as much as later frames
    num_frames = 1
    max_first_frame_size = MAX_BODY_SIZE - _topic_size.size - len(topic)

    if body_size <= max_first_frame_size:
        # return a tuple of just the first (only) frame
        return pack_first_frame(uid, num_frames, topic, body),

    remaining_size = body_size - max_first_frame_size
    num_frames += ceil(remaining_size / MAX_BODY_SIZE)

    frames = []
    start, end = 0, max_first_frame_size
    for i in range(num_frames):
        if not i:
            frames.append(pack_first_frame(uid, num_frames, topic,
                                           body[start:end]))
            continue
        start = end
        end = start + MAX_BODY_SIZE
        frames.append(pack_frame(uid, i, num_frames, body[start:end]))

    return tuple(frames)


def pack_first_frame(uid: int, total_frames: int, topic: bytes,
                     body: bytes) -> bytearray:
    body_size = len(body)
    topic_size = len(topic)
    header_size = _header.size + _topic_size.size + topic_size
    size = header_size + body_size
    vt = PROTOCOL_VERSION_UPPER | START_FRAME
    frame = 0

    buf = bytearray(header_size + body_size)
    # pack the header
    _header.pack_into(buf, 0, size, vt, uid, frame, total_frames)
    _topic_size.pack_into(buf, _header.size, topic_size)

    # pack the topic
    topic_start = _header.size + _topic_size.size
    topic_end = topic_start + topic_size
    buf[topic_start:topic_end] = topic

    # pack the body
    buf[topic_end:] = body

    return buf


def pack_frame(uid: int, frame: int, total_frames: int,
               body: bytes) -> bytearray:
    body_size = len(body)
    size = _header.size + body_size
    vt = PROTOCOL_VERSION_UPPER | CONTINUATION_FRAME

    buf = bytearray(_header.size + body_size)
    # pack the header
    _header.pack_into(buf, 0, size, vt, uid, frame, total_frames)

    # pack the body
    buf[_header.size:] = body

    return buf


def pack_drop_message(uid: int, frame: int, total_frames: int) -> bytearray:
    vt = PROTOCOL_VERSION_UPPER | MESSAGE_DROPPED
    buf = bytearray(_header.size)

    _header.pack_into(buf, 0, _header.size, vt, uid, frame, total_frames)

    return buf


def pack_request_message(uid: int, frame: int, total_frames: int) -> bytearray:
    vt = PROTOCOL_VERSION_UPPER | FRAME_REQUEST
    buf = bytearray(_header.size)

    _header.pack_into(buf, 0, _header.size, vt, uid, frame, total_frames)

    return buf


def set_response_frame_type(*frames):
    vt = PROTOCOL_VERSION_UPPER | FRAME_RESPONSE
    for frame in frames:
        frame[VERSION_TYPE_BYTE_POSITION] = vt
