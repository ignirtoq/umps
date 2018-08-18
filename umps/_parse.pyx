from cpython.buffer cimport (PyObject_GetBuffer, PyBuffer_Release,
                             PyBUF_ANY_CONTIGUOUS, PyBUF_SIMPLE)
from libc.string cimport memcpy

TYPE_MASK = 0xF
VERSION_MASK = 0xF0
# v1 message types
START_FRAME = 0x1
CONTINUATION_FRAME = 0x2
FRAME_REQUEST = 0x3
FRAME_RESPONSE = 0x4
MESSAGE_DROPPED = 0x5

MAX_UDP_SIZE = 512
FRAME_HEADER_SIZE = 13
FRAME_BODY_SIZE = MAX_UDP_SIZE - FRAME_HEADER_SIZE


cdef uint8_t _swapped_plat = (1 != htons(1))


cdef uint64_t ntoh_u64(uint64_t net_u64) nogil:
    cdef _u64_as_u32_array net_u32_2
    cdef _u64_as_u32_array host_u32_2

    if not _swapped_plat:
        # Network and host order the same, so return unmodified.
        return net_u64

    net_u32_2.u64 = net_u64
    host_u32_2.u32[1] = ntohl(net_u32_2.u32[0])
    host_u32_2.u32[0] = ntohl(net_u32_2.u32[1])
    return host_u32_2.u64


cdef uint64_t hton_u64(uint64_t host_u64) nogil:
    return ntoh_u64(host_u64)


cdef frame_header_t ntoh_frame_header_t(uint8_t* data) nogil:
    cdef frame_header_t *hdr = <frame_header_t*>data
    cdef frame_header_t out

    out.size = ntohs(hdr.size)
    out.vt = hdr.vt
    out.uid = ntoh_u64(hdr.uid)
    out.frame_number = hdr.frame_number
    out.total_frames = hdr.total_frames

    return out


cdef topic_t get_topic_from_frame(uint8_t* data) nogil:
    cdef size_t size_loc = sizeof(frame_header_t)
    cdef size_t topic_start = size_loc + 1
    cdef uint8_t topic_size = data[size_loc]
    cdef topic_t topic
    cdef size_t i

    topic.size = topic_size
    memcpy(&topic.value[0], &data[topic_start], topic_size)

    return topic


cdef bytes get_bytes_from_topic_t(topic_t topic):
    cdef bytes out = topic.value
    return out


cdef class Frame:

    @staticmethod
    def from_bytes(object frame_bytes):
        cdef Py_buffer bytes_buf
        cdef uint8_t *frame_buf
        cdef topic_t topic
        cdef bytes topic_bytes
        cdef size_t body_start
        cdef size_t buf_len = len(frame_bytes)
        cdef Frame frame = Frame()

        if buf_len < sizeof(frame_header_t):
            raise ValueError('data buffer smaller than header size: '
                             '%d < %d' % (<int>buf_len, sizeof(frame_header_t)))

        PyObject_GetBuffer(frame_bytes, &bytes_buf,
                           PyBUF_ANY_CONTIGUOUS | PyBUF_SIMPLE)
        try:
            frame_buf = <uint8_t*>bytes_buf.buf
            with nogil:
                memcpy(&frame._hdr, frame_buf, FRAME_HEADER_SIZE)
                topic.size = 0
                if (frame._hdr.vt & TYPE_MASK) == START_FRAME:
                    topic = get_topic_from_frame(frame_buf)
        finally:
            PyBuffer_Release(&bytes_buf)

        if topic.size:
            topic_bytes = get_bytes_from_topic_t(topic)
        else:
            topic_bytes = b''
        frame.topic = topic_bytes.decode('utf8')

        body_start = sizeof(frame_header_t) + (topic.size != 0) + topic.size
        frame.body = bytes(frame_bytes[body_start:])

        return frame

    @property
    def size(self):
        return ntohs(self._hdr.size)

    @size.setter
    def size(self, uint16_t new_size):
        self._hdr.size = htons(new_size)

    @property
    def protocol_version(self):
        return self._hdr.vt >> 4

    @protocol_version.setter
    def protocol_version(self, uint8_t version):
        self._hdr.vt = (self._hdr.vt & TYPE_MASK) | (version << 4)

    @property
    def frame_type(self):
        return self._hdr.vt & TYPE_MASK

    @frame_type.setter
    def frame_type(self, uint8_t new_type):
        self._hdr.vt = (self._hdr.vt & VERSION_MASK) | (new_type & TYPE_MASK)

    @property
    def uid(self):
        return ntoh_u64(self._hdr.uid)

    @uid.setter
    def uid(self, uint64_t new_uid):
        self._hdr.uid = hton_u64(new_uid)

    @property
    def frame_number(self):
        return self._hdr.frame_number

    @frame_number.setter
    def frame_number(self, uint8_t new_number):
        self._hdr.frame_number = new_number

    @property
    def total_frames(self):
        return self._hdr.total_frames

    @total_frames.setter
    def total_frames(self, uint8_t new_total):
        self._hdr.total_frames = new_total


cpdef list pack(uint64_t uid, unicode topic, bytes body):
    cdef Py_buffer bytearray_buf, topic_buf, body_buf
    cdef bytes topic_bytes = topic.encode()
    cdef size_t topic_size = len(topic_bytes)
    cdef size_t body_size = len(body)
    cdef size_t max_body_size = max_message_size(topic_size)
    cdef uint8_t total_frames = compute_total_frames(topic_size, body_size)
    cdef list ret_list = [None,] * total_frames
    cdef frame_t frame
    cdef size_t frame_size
    cdef size_t next_frame_start
    cdef bytearray py_frame
    cdef int i

    if topic_size > 256:
        raise ValueError('topic too long')

    if body_size > max_body_size:
        raise ValueError('message length exceeds maximum for topic: '
                         '%d > %d' % (<int>body_size, <int>max_body_size))

    PyObject_GetBuffer(topic_bytes, &topic_buf,
                       PyBUF_ANY_CONTIGUOUS | PyBUF_SIMPLE)
    PyObject_GetBuffer(body, &body_buf,
                       PyBUF_ANY_CONTIGUOUS | PyBUF_SIMPLE)
    try:
        # pack the first frame
        frame_size = FRAME_HEADER_SIZE + min(1 + topic_size + body_size,
                                             FRAME_BODY_SIZE)
        py_frame = bytearray(frame_size)
        PyObject_GetBuffer(py_frame, &bytearray_buf,
                           PyBUF_ANY_CONTIGUOUS | PyBUF_SIMPLE)
        try:
            next_frame_start = c_pack_start_frame(
                <frame_t*>bytearray_buf.buf, <uint16_t>frame_size, uid,
                total_frames, <uint8_t>topic_size, <uint8_t*>topic_buf.buf,
                body_size, <uint8_t*>body_buf.buf
            )
        finally:
            PyBuffer_Release(&bytearray_buf)
        ret_list[0] = py_frame

        # pack the rest of the frames
        for i in range(1, total_frames):
            frame_size = FRAME_HEADER_SIZE + min(body_size - next_frame_start,
                                                 FRAME_BODY_SIZE)
            py_frame = bytearray(frame_size)
            PyObject_GetBuffer(py_frame, &bytearray_buf,
                               PyBUF_ANY_CONTIGUOUS | PyBUF_SIMPLE)
            try:
                next_frame_start += c_pack_cont_frame(
                    <frame_t*>bytearray_buf.buf, <uint16_t>frame_size, uid, i,
                    total_frames, next_frame_start,
                    body_size - next_frame_start, <uint8_t*>body_buf.buf
                )
            finally:
                PyBuffer_Release(&bytearray_buf)
            ret_list[i] = py_frame
    finally:
        PyBuffer_Release(&topic_buf)
        PyBuffer_Release(&body_buf)

    return ret_list


cdef size_t max_message_size(size_t topic_size):
    return 255*FRAME_BODY_SIZE - (topic_size + 1)


cdef uint8_t compute_total_frames(size_t topic_size, size_t body_size) nogil:
    cdef size_t full_body_size = topic_size + body_size + 1  # topic size byte
    return <uint8_t> (full_body_size / FRAME_BODY_SIZE +
                      ((full_body_size % FRAME_BODY_SIZE) != 0))


cdef void c_set_frame_header(frame_header_t *hdr, uint16_t size,
                             uint8_t frame_type, uint64_t uid,
                             uint8_t frame_number, uint8_t total_frames) nogil:
    hdr.size         = htons(size)
    hdr.vt           = 1 << 4 | frame_type
    hdr.uid          = hton_u64(uid)
    hdr.frame_number = frame_number
    hdr.total_frames = total_frames


cdef size_t c_pack_start_frame(frame_t *frame, uint16_t size, uint64_t uid,
                               uint8_t total_frames, uint8_t topic_size,
                               uint8_t *topic, size_t body_size,
                               uint8_t *body) nogil:
    cdef size_t body_copied = min(body_size, FRAME_BODY_SIZE - (topic_size + 1))
    c_set_frame_header(&frame.hdr, size, START_FRAME, uid, 0, total_frames)
    frame.body[0] = topic_size
    memcpy(&frame.body[1], topic, topic_size)
    memcpy(&frame.body[1 + topic_size], body, body_copied)
    return body_copied


cdef size_t c_pack_cont_frame(frame_t *frame, uint16_t size, uint64_t uid,
                              uint8_t frame_number, uint8_t total_frames,
                              size_t body_start, size_t body_size_remaining,
                              uint8_t *body) nogil:
    cdef size_t size_copied = min(body_size_remaining, FRAME_BODY_SIZE)
    c_set_frame_header(&frame.hdr, size, CONTINUATION_FRAME, uid, frame_number,
                       total_frames)
    memcpy(&frame.body, body+body_start, size_copied)
    return size_copied
