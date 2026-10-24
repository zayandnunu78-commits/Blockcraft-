/**
 * Copyright (c) 2006-2023 LOVE Development Team
 *
 * This software is provided 'as-is', without any express or implied
 * warranty.  In no event will the authors be held liable for any damages
 * arising from the use of this software.
 *
 * Permission is granted to anyone to use this software for any purpose,
 * including commercial applications, and to alter it and redistribute it
 * freely, subject to the following restrictions:
 *
 * 1. The origin of this software must not be misrepresented; you must not
 *    claim that you wrote the original software. If you use this software
 *    in a product, an acknowledgment in the product documentation would be
 *    appreciated but is not required.
 * 2. Altered source versions must be plainly marked as such, and must not be
 *    misrepresented as being the original software.
 * 3. This notice may not be removed or altered from any source distribution.
 **/

// LOVE
#include "wrap_System.h"
#include "sdl/System.h"

#ifdef LOVE_WINDOWS_UWP
#include "uwp/HttpDownload.h"
#include "uwp/HttpRequest.h"
#endif

namespace love
{
namespace system
{

#define instance() (Module::getInstance<System>(Module::M_SYSTEM))

int w_getOS(lua_State *L)
{
	luax_pushstring(L, instance()->getOS());
	return 1;
}

int w_getProcessorCount(lua_State *L)
{
	lua_pushinteger(L, instance()->getProcessorCount());
	return 1;
}

int w_setClipboardText(lua_State *L)
{
	const char *text = luaL_checkstring(L, 1);
	luax_catchexcept(L, [&]() { instance()->setClipboardText(text); });
	return 0;
}

int w_getClipboardText(lua_State *L)
{
	std::string text;
	luax_catchexcept(L, [&]() { text = instance()->getClipboardText(); });
	luax_pushstring(L, text);
	return 1;
}

int w_getPowerInfo(lua_State *L)
{
	int seconds = -1, percent = -1;
	const char *str;

	System::PowerState state = instance()->getPowerInfo(seconds, percent);

	if (!System::getConstant(state, str))
		str = "unknown";

	lua_pushstring(L, str);

	if (percent >= 0)
		lua_pushinteger(L, percent);
	else
		lua_pushnil(L);

	if (seconds >= 0)
		lua_pushinteger(L, seconds);
	else
		lua_pushnil(L);

	return 3;
}

int w_openURL(lua_State *L)
{
	std::string url = luax_checkstring(L, 1);
	luax_pushboolean(L, instance()->openURL(url));
	return 1;
}

int w_vibrate(lua_State *L)
{
	double seconds = luaL_optnumber(L, 1, 0.5);
	instance()->vibrate(seconds);
	return 0;
}

int w_hasBackgroundMusic(lua_State *L)
{
	lua_pushboolean(L, instance()->hasBackgroundMusic());
	return 1;
}

#ifdef LOVE_WINDOWS_UWP
int w_httpDownload(lua_State *L)
{
	const char *url = luaL_checkstring(L, 1);
	const char *path = luaL_checkstring(L, 2);
	const char *userAgent = luaL_optstring(L, 3, "love");
	const char *accept = luaL_optstring(L, 4, nullptr);
	luax_pushboolean(L, uwp::httpDownload(url, path, userAgent, accept));
	return 1;
}

int w_httpRequest(lua_State *L)
{
	std::string url = luax_checkstring(L, 1);
	std::string method = luax_checkstring(L, 2);
	std::vector<uwp::HttpHeader> headers;

	if (!lua_isnoneornil(L, 3))
	{
		luaL_checktype(L, 3, LUA_TTABLE);
		size_t count = luax_objlen(L, 3);
		if (count % 2 != 0)
			return luaL_error(L, "HTTP headers must contain name-value pairs.");

		for (size_t i = 1; i <= count; i += 2)
		{
			lua_rawgeti(L, 3, (int) i);
			std::string name = luax_checkstring(L, -1);
			lua_pop(L, 1);
			lua_rawgeti(L, 3, (int) i + 1);
			std::string value = luax_checkstring(L, -1);
			lua_pop(L, 1);
			headers.push_back({ name, value });
		}
	}

	std::string body;
	const std::string *bodyptr = nullptr;
	if (!lua_isnoneornil(L, 4))
	{
		body = luax_checkstring(L, 4);
		bodyptr = &body;
	}

	std::string userAgent = luaL_optstring(L, 5, "love");
	std::string result = uwp::httpRequest(url, method, headers, bodyptr, userAgent);
	lua_pushlstring(L, result.data(), result.size());
	return 1;
}
#endif

static const luaL_Reg functions[] =
{
	{ "getOS", w_getOS },
	{ "getProcessorCount", w_getProcessorCount },
	{ "setClipboardText", w_setClipboardText },
	{ "getClipboardText", w_getClipboardText },
	{ "getPowerInfo", w_getPowerInfo },
	{ "openURL", w_openURL },
	{ "vibrate", w_vibrate },
	{ "hasBackgroundMusic", w_hasBackgroundMusic },
#ifdef LOVE_WINDOWS_UWP
	{ "httpDownload", w_httpDownload },
	{ "httpRequest", w_httpRequest },
#endif
	{ 0, 0 }
};

extern "C" int luaopen_love_system(lua_State *L)
{
	System *instance = instance();
	if (instance == nullptr)
	{
		instance = new love::system::sdl::System();
	}
	else
		instance->retain();

	WrappedModule w;
	w.module = instance;
	w.name = "system";
	w.type = &Module::type;
	w.functions = functions;
	w.types = nullptr;

	return luax_register_module(L, w);
}

} // system
} // love
