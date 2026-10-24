include(FetchContent)

function(love_add_luajit_uwp target)
	if(NOT MSVC OR NOT CMAKE_SYSTEM_NAME STREQUAL "WindowsStore")
		message(FATAL_ERROR "The bundled LuaJIT target is only for MSVC WindowsStore builds.")
	endif()
	if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
		message(FATAL_ERROR "The bundled LuaJIT target currently supports x64 only.")
	endif()

	FetchContent_Declare(love_luajit_source
		GIT_REPOSITORY https://github.com/LuaJIT/LuaJIT.git
		GIT_TAG 4886b676a698acc4bbdf54adfabb3e33a8c020e8
	)
	FetchContent_MakeAvailable(love_luajit_source)
	set(LOVE_LUAJIT_SOURCE_DIR "${love_luajit_source_SOURCE_DIR}" PARENT_SCOPE)

	set(lj_src "${love_luajit_source_SOURCE_DIR}/src")
	set(lj_gen "${CMAKE_CURRENT_BINARY_DIR}/luajit-generated")
	set(lj_generated
		"${lj_gen}/lj_vm.obj"
		"${lj_gen}/luajit.h"
		"${lj_gen}/lj_bcdef.h"
		"${lj_gen}/lj_ffdef.h"
		"${lj_gen}/lj_libdef.h"
		"${lj_gen}/lj_recdef.h"
		"${lj_gen}/lj_folddef.h"
		"${lj_gen}/jit/vmdef.lua"
	)

	file(GLOB lj_generator_inputs CONFIGURE_DEPENDS
		"${love_luajit_source_SOURCE_DIR}/dynasm/*.lua"
		"${lj_src}/host/*.c"
		"${lj_src}/host/*.h"
		"${lj_src}/lib_*.c"
		"${lj_src}/lj_*.c"
		"${lj_src}/lj_*.h"
		"${lj_src}/vm_x64.dasc"
	)
	add_custom_command(
		OUTPUT ${lj_generated}
		COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
			"${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../uwp/generate-luajit.ps1"
			-SourceRoot "${love_luajit_source_SOURCE_DIR}"
			-OutputRoot "${lj_gen}"
		DEPENDS
			"${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../uwp/generate-luajit.ps1"
			${lj_generator_inputs}
		COMMENT "Generating LuaJIT x64 VM and library definitions"
		VERBATIM
	)

	file(GLOB lj_runtime_sources CONFIGURE_DEPENDS
		"${lj_src}/lj_*.c"
		"${lj_src}/lib_*.c"
	)

	set_source_files_properties("${lj_gen}/lj_vm.obj" PROPERTIES
		EXTERNAL_OBJECT TRUE
		GENERATED TRUE
	)
	add_library(${target} SHARED
		${lj_runtime_sources}
		${lj_generated}
	)
	target_include_directories(${target} PUBLIC "${lj_src}" PRIVATE "${lj_gen}")
	target_compile_definitions(${target} PRIVATE
		_UWP=1
		LUA_BUILD_AS_DLL=1
		_CRT_SECURE_NO_DEPRECATE=1
		_CRT_STDIO_INLINE=__declspec\(dllexport\)__inline
	)
	target_compile_options(${target} PRIVATE /W3)
	target_link_libraries(${target} PRIVATE WindowsApp.lib)
	set_target_properties(${target} PROPERTIES
		OUTPUT_NAME lua51
		PREFIX ""
	)
endfunction()
