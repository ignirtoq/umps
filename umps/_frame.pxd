from libc.stdint cimport uint8_t, uint16_t, uint32_t, uint64_t


IF UNAME_SYSNAME == "Windows":
    cdef extern from "WinSock2.h" nogil:
        int htons (int)
        long htonl (long)
        int ntohs (int)
        long ntohl (long)
ELSE:
    cdef extern from "arpa/inet.h" nogil:
        int htons (int)
        long htonl (long)
        int ntohs (int)
        long ntohl (long)


cdef uint8_t TYPE_MASK
cdef uint8_t VERSION_MASK
# v1 message types
cdef uint8_t START_FRAME
cdef uint8_t CONTINUATION_FRAME
cdef uint8_t FRAME_REQUEST
cdef uint8_t FRAME_RESPONSE
cdef uint8_t MESSAGE_DROPPED


cdef union _u64_as_u32_array:
    uint64_t u64
    uint32_t u32[2]


cdef packed struct frame_header_t:
    uint16_t size
    uint8_t  vt
    uint64_t uid
    uint8_t  frame_number
    uint8_t  total_frames


DEF MAX_UDP_SIZE = 512
cdef uint16_t MAX_UDP_SIZE
# This should use something safer, like sizeof(), but Cython doesn't support a
# call to sizeof() in a DEF statement.
DEF FRAME_HEADER_SIZE = 13
cdef uint16_t FRAME_HEADER_SIZE
DEF FRAME_BODY_SIZE = MAX_UDP_SIZE - FRAME_HEADER_SIZE
cdef uint16_t FRAME_BODY_SIZE


cdef packed struct frame_t:
    frame_header_t hdr
    uint8_t        body[FRAME_BODY_SIZE]


cdef uint64_t ntoh_u64(uint64_t net_u64) nogil
cdef uint64_t hton_u64(uint64_t host_u64) nogil

cdef frame_header_t ntoh_frame_header_t(frame_header_t* data) nogil
cdef frame_header_t hton_frame_header_t(frame_header_t* data) nogil
