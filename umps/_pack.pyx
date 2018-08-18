from cpython.buffer cimport (PyObject_GetBuffer, PyBuffer_Release,
                             PyBUF_ANY_CONTIGUOUS, PyBUF_SIMPLE)
from libc.string cimport memcpy
from libc.stdint cimport uint8_t, uint16_t, uint64_t

from ._frame cimport (START_FRAME, CONTINUATION_FRAME, FRAME_HEADER_SIZE,
                      FRAME_BODY_SIZE, htons, hton_u64, frame_header_t, frame_t)


cpdef list pack(uint64_t uid, unicode topic, object body):
    cdef Py_buffer bytearray_buf, topic_buf, body_buf
    cdef bytes body_bytes = (body if isinstance(body, bytes) else
                             body.encode('utf-8'))
    cdef bytes topic_bytes = topic.encode()
    cdef size_t topic_size = len(topic_bytes)
    cdef size_t body_size = len(body_bytes)
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
    PyObject_GetBuffer(body_bytes, &body_buf,
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
