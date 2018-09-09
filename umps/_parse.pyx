from cpython.buffer cimport (PyObject_GetBuffer, PyBuffer_Release,
                             PyBUF_ANY_CONTIGUOUS, PyBUF_SIMPLE)
from libc.string cimport memcpy
from libc.stdint cimport uint16_t, uint64_t

from ._frame cimport (TYPE_MASK, VERSION_MASK, START_FRAME, FRAME_RESPONSE,
                      FRAME_HEADER_SIZE,
                      htons, ntohs, ntoh_u64, hton_u64,
                      frame_header_t)

from libc.stdint cimport uint8_t


cdef packed struct topic_t:
    uint8_t size
    uint8_t value[256]


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
    cdef bytes out = topic.value[:topic.size]
    return out


cdef class Frame:

    cdef frame_header_t _hdr
    cdef public unicode topic
    cdef public bytes body

    @staticmethod
    def parse(object frame_bytes):
        cdef Py_buffer bytes_buf
        cdef uint8_t *frame_buf
        cdef topic_t topic
        cdef bytes topic_bytes
        cdef size_t body_start
        cdef size_t buf_len = len(frame_bytes)
        cdef Frame frame = Frame()
        cdef uint8_t frame_type

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
                frame_type = frame._hdr.vt & TYPE_MASK
                if frame._hdr.frame_number == 0 and (
                        frame_type == START_FRAME or
                        frame_type == FRAME_RESPONSE):
                    topic = get_topic_from_frame(frame_buf)
        finally:
            PyBuffer_Release(&bytes_buf)

        if topic.size:
            topic_bytes = get_bytes_from_topic_t(topic)
        else:
            topic.size = 0
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
