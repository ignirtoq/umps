# cython: embedsignature = True

cdef long long _hash_v1(void* string, int length, long long nbins) nogil:
    cdef long long output_bin = 7
    cdef int i = 0

    for i in range(length):
        output_bin = (output_bin*31 + (<char*>string)[i]) % nbins

    return output_bin


def hash_v1(unicode string, long long nbins):
    """
    Hash a unicode string into one of a given number of bins.
    """
    cdef bytes string_bytes = string.encode('utf8')
    cdef unsigned char *c_string = string_bytes
    cdef int length = len(c_string)
    cdef long long string_hash = 0

    with nogil:
        string_hash = _hash_v1(c_string, length, nbins)

    return string_hash
