def hash_v1(string: str, nbins: int) -> int:
    output_bin: int = 7
    for char in string.encode('utf-8'):
        output_bin = (output_bin*31 + char) % nbins
    return output_bin
