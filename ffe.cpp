#include "lua.h"
#include "lauxlib.h"

int hello(lua_State *L) {

  return 1;
}

static const struct luaL_Reg functions [] = {
  {"hello", hello},
  {NULL, NULL}
};

int luaopen_hello(lua_State *L) {
  luaL_register(L, "hello", functions);
  return 1;
}
