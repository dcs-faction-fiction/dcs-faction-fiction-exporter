#!/bin/bash -x

INCLUDE="/c/Development/Lua5.1/include"
LIBRARIES="/c/Development/Lua5.1/lib"

gcc -shared -o ffe.dll -I$INCLUDE ffe.c  $LIBRARIES/lua5.1.lib
