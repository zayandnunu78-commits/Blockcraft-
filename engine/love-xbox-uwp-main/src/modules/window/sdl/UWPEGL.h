#pragma once

#include <optional>

namespace love
{
namespace window
{
namespace sdl
{

struct EGLSurfaceSize
{
	int width;
	int height;
};

std::optional<EGLSurfaceSize> getEGLSurfaceSize();

} // sdl
} // window
} // love
