#!/bin/bash

INCLUDE="/c/Development/lua/include"
LIBRARIES="/c/Development/lua/lib"

CMD="g++ -shared -o ffe.dll -I$INCLUDE $LIBRARIES/liblua.dll.a ffe.cpp "
echo $CMD
$CMD
