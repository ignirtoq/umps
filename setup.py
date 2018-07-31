from setuptools import setup, find_packages
import re

name = 'umps'
description = 'Publish-subscribe protocol based on UDP multicast'
with open('umps/_version.py') as ver_file:
    ver_text = ver_file.read()
pattern = re.compile(r"^version = ['\"]([^'\"]*)['\"]", re.MULTILINE)
version = pattern.search(ver_text).group(1)

setup(
    name=name,
    description=description,
    version=version,
    packages=find_packages(),
      )
