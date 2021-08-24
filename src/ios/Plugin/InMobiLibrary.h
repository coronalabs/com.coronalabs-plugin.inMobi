//----------------------------------------------------------------------------
// InMobiLibrary.h
//
// Copyright (c) 2016 Corona Labs. All rights reserved.
//----------------------------------------------------------------------------

#ifndef _InMobiLibrary_H_
#define _InMobiLibrary_H_

#include "CoronaLua.h"
#include "CoronaMacros.h"

// This corresponds to the name of the library, e.g. [Lua] require "plugin.library"
// where the '.' is replaced with '_'
CORONA_EXPORT int luaopen_plugin_inMobi(lua_State *L);

#endif // _InMobiLibrary_H_
