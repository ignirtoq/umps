from cpython.buffer cimport (PyObject_GetBuffer, PyBuffer_Release,
                             PyBUF_ANY_CONTIGUOUS, PyBUF_SIMPLE)
from libc.stdint cimport uint8_t, uint16_t, uint32_t, uint64_t


IF UNAME_SYSNAME == "Windows":
    cdef extern from "WinSock2.h" nogil:
        int htons (int)
        int htonl (int)
        int ntohl (int)
        int ntohs (int)
ELSE:
    cdef extern from "arpa/inet.h" nogil:
        int htons (int)
        int htonl (int)
        int ntohl (int)
        int ntohs (int)


cdef union _u64_as_u32_array:
    uint64_t u64
    uint32_t u32[2]


cdef packed struct frame_header_t:
    uint16_t size
    uint8_t  vt
    uint64_t uid
    uint8_t  frame_number
    uint8_t  total_frames


cdef struct topic_t:
    uint8_t size
    uint8_t value[256]


cdef class Frame:
    cdef public uint16_t size
    cdef public uint8_t protocol_version
    cdef public uint8_t frame_type
    cdef public uint64_t uid
    cdef public uint8_t frame_number
    cdef public uint8_t total_frames
    cdef public unicode topic
    cdef public bytes   body

    cdef void from_frame_header_t(Frame self, frame_header_t hdr)
