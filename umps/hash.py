def hash_v1(string: str, nbins: int) -> int:
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
    output_bin: int = 7
    for char in string.encode('utf-8'):
        output_bin = (output_bin*31 + char) % nbins
    return output_bin


# If the C extension is available, use it.
_hash_v1 = hash_v1  # Save Python implementation for unit testing.
try:
    from ._hash import hash_v1
except ImportError:
    pass
