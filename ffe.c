#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

int hello(lua_State *L) {
  lua_pushstring(L, "TEST");
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
