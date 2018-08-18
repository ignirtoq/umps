import os
import re
from setuptools import setup, find_packages
from setuptools.extension import Extension
try:
    from Cython.Build import cythonize
    HAVE_CYTHON = True
except ImportError:
    HAVE_CYTHON = False


name = 'umps'
description = 'Publish-subscribe protocol based on UDP multicast'
with open('umps/_version.py') as ver_file:
    ver_text = ver_file.read()
pattern = re.compile(r"^version = ['\"]([^'\"]*)['\"]", re.MULTILINE)
version = pattern.search(ver_text).group(1)


frame_libs = []
if os.name == 'nt':
    frame_libs.append('Ws2_32')
ext_suffix = '.pyx' if HAVE_CYTHON else '.c'
extensions = [
    Extension("umps._hash", ["umps/_hash"+ext_suffix], optional=True),
    Extension("umps._frame", ["umps/_frame"+ext_suffix], optional=True,
              libraries=frame_libs),
    Extension("umps._pack", ["umps/_pack"+ext_suffix], optional=True,
              libraries=frame_libs),
    Extension("umps._parse", ["umps/_parse"+ext_suffix], optional=True,
              libraries=frame_libs),
]
if HAVE_CYTHON:
    extensions = cythonize(extensions)


setup(
    name=name,
    description=description,
    version=version,
    packages=find_packages(),
    ext_modules=extensions,
    zip_safe=False,
      )
