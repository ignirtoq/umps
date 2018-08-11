cdef uint32_t MAX_UDP_SIZE = 512


# v1 message types
cdef uint8_t TYPE_MASK = 0xF
cdef uint8_t START_FRAME = 0x1
cdef uint8_t CONTINUATION_FRAME = 0x2
cdef uint8_t FRAME_REQUEST = 0x3
cdef uint8_t FRAME_RESPONSE = 0x4
cdef uint8_t MESSAGE_DROPPED = 0x5


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
    for i in xrange(topic_size):
        topic.value[i] = data[topic_start+i]

    return topic


cdef bytes get_bytes_from_topic_t(topic_t topic):
    cdef bytes out = topic.value
    return out


cdef class Frame:

    cdef void from_frame_header_t(Frame self, frame_header_t hdr):
        self.size = hdr.size
        self.protocol_version = hdr.vt >> 4
        self.frame_type = hdr.vt & TYPE_MASK
        self.uid = hdr.uid
        self.frame_number = hdr.frame_number
        self.total_frames = hdr.total_frames

    @staticmethod
    def from_bytes(bytes frame_bytes):
        cdef Py_buffer bytes_buf
        cdef uint8_t *frame_buf
        cdef frame_header_t hdr
        cdef topic_t topic
        cdef bytes topic_bytes
        cdef size_t body_start
        cdef size_t buf_len = len(frame_bytes)
        cdef Frame frame = Frame()

        if buf_len < sizeof(frame_header_t):
            raise ValueError('data buffer smaller than header size: '
                             '%d vs %d' % (buf_len,
                                           sizeof(frame_header_t)))

        PyObject_GetBuffer(frame_bytes, &bytes_buf,
                           PyBUF_ANY_CONTIGUOUS | PyBUF_SIMPLE)
        try:
            frame_buf = <uint8_t*>bytes_buf.buf
            with nogil:
                hdr = ntoh_frame_header_t(frame_buf)
                topic.size = 0
                if (hdr.vt & TYPE_MASK) == START_FRAME:
                    topic = get_topic_from_frame(frame_buf)
        finally:
            PyBuffer_Release(&bytes_buf)

        frame.from_frame_header_t(hdr)
        if topic.size:
            topic_bytes = get_bytes_from_topic_t(topic)
        else:
            topic_bytes = b''
        frame.topic = topic_bytes.decode('utf8')

        body_start = sizeof(frame_header_t) + (topic.size != 0) + topic.size
        frame.body = frame_bytes[body_start:]

        return frame
