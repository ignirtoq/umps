import random
import unittest

from umps import hash


def random_unicode(length):
    # Create a list of unicode characters within the range 0000-D7FF
    random_unicodes = [chr(random.randrange(1, 0xD7FF)) for _ in range(length)]
    return ''.join(random_unicodes)


if hash._hash_v1 is not hash.hash_v1:
    py_hash = hash._hash_v1
    c_hash = hash.hash_v1


    class CHashComparison(unittest.TestCase):
        NBINS = 1024
        ITERS = 2**16

        def test_hash_output_match(self):
            # Seed generator for reproducible test.
            random.seed(0)
            for _ in range(self.ITERS):
                test_string = random_unicode(64)
                self.assertEqual(py_hash(test_string, self.NBINS),
                                 c_hash(test_string, self.NBINS))
