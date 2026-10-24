#include "UWPEGL.h"

#include <SDL_loadso.h>

namespace love
{
namespace window
{
namespace sdl
{

std::optional<EGLSurfaceSize> getEGLSurfaceSize()
{
	using EGLBoolean = unsigned int;
	using EGLDisplay = void *;
	using EGLint = int;
	using EGLSurface = void *;

	constexpr EGLint EGL_WIDTH = 0x3057;
	constexpr EGLint EGL_HEIGHT = 0x3056;
	constexpr EGLint EGL_DRAW = 0x3059;

	using GetCurrentDisplay = EGLDisplay (*)();
	using GetCurrentSurface = EGLSurface (*)(EGLint);
	using QuerySurface = EGLBoolean (*)(EGLDisplay, EGLSurface, EGLint, EGLint *);

	static void *library = SDL_LoadObject("libEGL.dll");
	if (!library)
		return std::nullopt;

	auto getCurrentDisplay = reinterpret_cast<GetCurrentDisplay>(SDL_LoadFunction(library, "eglGetCurrentDisplay"));
	auto getCurrentSurface = reinterpret_cast<GetCurrentSurface>(SDL_LoadFunction(library, "eglGetCurrentSurface"));
	auto querySurface = reinterpret_cast<QuerySurface>(SDL_LoadFunction(library, "eglQuerySurface"));
	if (!getCurrentDisplay || !getCurrentSurface || !querySurface)
		return std::nullopt;

	EGLDisplay display = getCurrentDisplay();
	EGLSurface surface = getCurrentSurface(EGL_DRAW);
	if (!display || !surface)
		return std::nullopt;

	EGLint width = 0;
	EGLint height = 0;
	if (!querySurface(display, surface, EGL_WIDTH, &width)
		|| !querySurface(display, surface, EGL_HEIGHT, &height)
		|| width <= 0 || height <= 0)
		return std::nullopt;

	return EGLSurfaceSize{width, height};
}

} // sdl
} // window
} // love
