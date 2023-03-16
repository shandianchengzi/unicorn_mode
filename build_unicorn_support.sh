#!/bin/sh
#
# EDG says: This script slightly tweaked to make installation more smooth
#
# american fuzzy lop - Unicorn-Mode build script
# --------------------------------------
#
# Written by Nathan Voss <njvoss99@gmail.com>
# 
# Adapted from code by Andrew Griffiths <agriffiths@google.com> and
#                      Michal Zalewski <lcamtuf@google.com>
#
# Copyright 2017 Battelle Memorial Institute. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at:
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# This script downloads, patches, and builds a version of Unicorn with
# minor tweaks to allow Unicorn-emulated binaries to be run under
# afl-fuzz. 
#
# The modifications reside in patches/*. The standalone Unicorn library
# will be written to /usr/lib/libunicornafl.so, and the Python bindings
# will be installed system-wide.
#
# You must make sure that Unicorn Engine is not already installed before
# running this script. If it is, please uninstall it first.

UNICORN_URL="https://github.com/unicorn-engine/unicorn/archive/1.0.3.tar.gz"

echo "================================================="
echo "Unicorn-AFL build script"
echo "================================================="
echo

echo "[*] Performing basic sanity checks..."

#if [ "$(id -u)" != "0" ]; then
#
#   echo "[-] Error: This script must be run as root/sudo" 
#   exit 1
#
#fi

if [ ! "`uname -s`" = "Linux" ]; then

  echo "[-] Error: Unicorn instrumentation is supported only on Linux."
  exit 1

fi

ldconfig -p | grep libunicorn > /dev/null;
if [ $? -eq 0 ]; then

  echo -n "[?] Unicorn Engine appears to already be installed on the system. Continuing will overwrite the existing installation. Continue (y/n)?"
  
  read answer
  if ! echo "$answer" | grep -iq "^y" ;then

    exit 1

  fi

fi

if [ ! -f "patches/afl-unicorn-cpu-inl.h" -o ! -f "../config.h" ]; then

  echo "[-] Error: key files not found - wrong working directory?"
  exit 1

fi

if [ ! -f "../afl-showmap" ]; then

  echo "[-] Error: ../afl-showmap not found - compile AFL first!"
  exit 1

fi

for i in wget python automake autoconf sha384sum; do

  T=`which "$i" 2>/dev/null`

  if [ "$T" = "" ]; then

    echo "[-] Error: '$i' not found. Run 'sudo apt-get install $i'."
    exit 1

  fi

done

# EDG: easy_install?? What are we? Cavepeople?
#if ! which easy_install > /dev/null; then
#
#  echo "[-] Error: Python setup-tools not found. Run 'sudo apt-get install python-setuptools'."
#  exit 1

#fi

if echo "$CC" | grep -qF /afl-; then

  echo "[-] Error: do not use afl-gcc or afl-clang to compile this tool."
  exit 1

fi

echo "[+] All checks passed!"

wget $UNICORN_URL

ARCHIVE="`basename -- "$UNICORN_URL"`"

CKSUM=`sha384sum -- "$ARCHIVE" 2>/dev/null | cut -d' ' -f1`

echo "[*] Uncompressing archive (this will take a while)..."

rm -rf "unicorn-1.0.3" || exit 1
tar xzf "$ARCHIVE" || exit 1

echo "[+] Unpacking successful."

# rm -rf "$ARCHIVE" || exit 1

echo "[*] Applying patches..."

cd "unicorn-1.0.3" && patch -p1 <../patches/commit.patch && cd .. || exit 1

echo "[+] Patching done."

echo "[*] Configuring Unicorn build..."

cd "unicorn-1.0.3" || exit 1

# No custom config necessary at the moment. Consider optimizations.
#CFLAGS="-O3" ./configure || exit 1

echo "[+] Configuration complete."

echo "[*] Attempting to build Unicorn (fingers crossed!)..."

make || exit 1

echo "[+] Build process successful!"

echo "[*] Installing patched unicorn binaries to local system..."

make && sudo make install || exit 1

echo "[+] Unicorn installed successfully."

echo "[*] Building Unicorn python bindings..."

cd bindings/python || exit 1
python3 setup.py install || exit 1
cd ../../ || exit 1

echo "[+] Unicorn Python bindings installed successfully"

# Compile the sample, run it, verify that it works!
echo "[*] Testing unicorn-mode functionality by running a sample test harness under afl-unicorn"

cd ../samples/simple || exit 1

# Run afl-showmap on the sample application. If anything comes out then it must have worked!
unset AFL_INST_RATIO
echo 0 | ../../../afl-showmap -U -m none -q -o .test-instr0 -- python3 simple_test_harness.py ./sample_inputs/sample1.bin || exit 1

if [ -s .test-instr0 ]
then
  
  echo "[+] Instrumentation tests passed. "
  echo "[+] All set, you can now use Unicorn mode (-U) in afl-fuzz!"
  RETVAL=0

else

  echo "[-] Error: Unicorn mode doesn't seem to work!"
  RETVAL=1

fi

rm -f .test-instr0

exit $RETVAL