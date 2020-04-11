#!/bin/bash -x

INCLUDE="/cygdrive/c/Development/lua64/include"
LIBRARIES="/cygdrive/c/Development/lua64"

gcc -m64 -shared -o ffe.dll -I$INCLUDE ffe.c $LIBRARIES/liblua5.1.a