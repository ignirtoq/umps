# cython: embedsignature = True

ctypedef unsigned char char_type_t
ctypedef long long bin_size_t


cdef bin_size_t c_hash_v1(char_type_t* string, size_t length,
                          bin_size_t nbins) nogil:
    cdef bin_size_t output_bin = 7
    cdef size_t i = 0

    for i in xrange(length):
        output_bin = (output_bin*31 + string[i]) % nbins

    return output_bin


cpdef hash_v1(unicode string, bin_size_t nbins):
    """
    Hash a unicode string into one of a given number of bins.

    Parameters
    ----------
    string : str
        Desired string to hash.
    nbins : int
        Total number of bins available for the string to hash into.

    Returns
    -------
    int
        A value from 0 to nbins-1 representing the bin the string hashes to.
    """
    cdef bytes string_bytes = string.encode('utf8')
    cdef size_t length = len(string_bytes)
    cdef char_type_t* c_string = string_bytes
    cdef bin_size_t string_hash = 0

    with nogil:
        string_hash = c_hash_v1(c_string, length, nbins)

    return string_hash

