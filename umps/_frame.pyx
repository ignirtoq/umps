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
MAX_TOPIC_SIZE = 255


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


cdef frame_header_t ntoh_frame_header_t(frame_header_t* hdr) nogil:
    cdef frame_header_t out

    out.size = ntohs(hdr.size)
    out.vt = hdr.vt
    out.uid = ntoh_u64(hdr.uid)
    out.frame_number = hdr.frame_number
    out.total_frames = hdr.total_frames

    return out


cdef frame_header_t hton_frame_header_t(frame_header_t* data) nogil:
    return ntoh_frame_header_t(data)
