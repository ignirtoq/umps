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
with open('umps/_version.py', encoding='utf-8') as ver_file:
    ver_text = ver_file.read()
pattern = re.compile(r"^version = ['\"]([^'\"]*)['\"]", re.MULTILINE)
version = pattern.search(ver_text).group(1)
with open('README.md', encoding='utf-8') as f:
    long_description = f.read()


if HAVE_CYTHON:
    frame_libs = []
    if os.name == 'nt':
        frame_libs.append('Ws2_32')
    extensions = cythonize([
        Extension("umps._hash", ["umps/_hash.pyx"], optional=True),
        Extension("umps._frame", ["umps/_frame.pyx"], optional=True,
                  libraries=frame_libs),
        Extension("umps._pack", ["umps/_pack.pyx"], optional=True,
                  libraries=frame_libs),
        Extension("umps._parse", ["umps/_parse.pyx"], optional=True,
                  libraries=frame_libs),
    ])
else:
    extensions = None


setup(
    name=name,
    description=description,
    long_description=long_description,
    long_description_content_type="text/markdown",
    url='https://github.com/ignirtoq/umps',
    author='Jeffrey Bouas',
    author_email='ignirtoq+umps@gmail.com',
    version=version,
    license='MIT',
    classifiers=[
        'Development Status :: 3 - Alpha',
        'Intended Audience :: Developers',
        'License :: OSI Approved :: MIT License',
        'Operating System :: OS Independent',
        'Programming Language :: Python',
        'Programming Language :: Python :: 3',
        'Programming Language :: Python :: 3.5',
        'Programming Language :: Python :: 3.6',
    ],
    packages=find_packages(),
    ext_modules=extensions,
    zip_safe=False,
    python_requires='>=3.5'
      )
