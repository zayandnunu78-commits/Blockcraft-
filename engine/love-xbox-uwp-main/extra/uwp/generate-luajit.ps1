param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [Parameter(Mandatory = $true)]
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$src = Join-Path $source 'src'
$dynasm = Join-Path $source 'dynasm'
$output = [System.IO.Path]::GetFullPath($OutputRoot)
$hostOutput = Join-Path $output 'host'
$jitOutput = Join-Path $output 'jit'
New-Item -ItemType Directory -Force -Path $output, $hostOutput, $jitOutput | Out-Null

$compiler = (Get-Command cl.exe -ErrorAction Stop).Source
$linker = (Get-Command link.exe -ErrorAction Stop).Source
$compilerBin = Split-Path -Parent $compiler
$msvcRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $compilerBin))
$desktopVcLib = Join-Path $msvcRoot 'lib\x64'
$kitsRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Lib'
$sdkVersion = Get-ChildItem -LiteralPath $kitsRoot -Directory |
    Where-Object {
        (Test-Path -LiteralPath (Join-Path $_.FullName 'ucrt\x64\ucrt.lib')) -and
        (Test-Path -LiteralPath (Join-Path $_.FullName 'um\x64\kernel32.lib'))
    } |
    Sort-Object { [version]$_.Name } -Descending |
    Select-Object -First 1
if (-not (Test-Path -LiteralPath (Join-Path $desktopVcLib 'libcmt.lib')) -or -not $sdkVersion) {
    throw 'Could not locate the desktop MSVC and Windows SDK libraries required by LuaJIT host generators.'
}
$hostLinkPaths = @(
    "/libpath:$desktopVcLib",
    "/libpath:$(Join-Path $sdkVersion.FullName 'ucrt\x64')",
    "/libpath:$(Join-Path $sdkVersion.FullName 'um\x64')"
)

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Native command failed ($LASTEXITCODE): $FilePath"
    }
}

$commonHostFlags = @(
    '/nologo', '/c', '/O2', '/W3',
    '/D_CRT_SECURE_NO_DEPRECATE',
    '/D_CRT_STDIO_INLINE=__declspec(dllexport)__inline'
)

$miniObject = Join-Path $hostOutput 'minilua.obj'
$miniExe = Join-Path $hostOutput 'minilua.exe'
Invoke-Native $compiler ($commonHostFlags + @(
    "/Fo$miniObject",
    (Join-Path $src 'host\minilua.c')
))
Invoke-Native $linker (@('/nologo', "/out:$miniExe", $miniObject) + $hostLinkPaths)

$generatedLuaJitHeader = Join-Path $output 'luajit.h'
$generatedRelver = Join-Path $output 'luajit_relver.txt'
$git = Get-Command git.exe -ErrorAction SilentlyContinue
$rollingVersion = if ($git) {
    (& $git.Source -C $source show -s '--format=%ct' HEAD).Trim()
} else {
    'ROLLING'
}
[System.IO.File]::WriteAllText($generatedRelver, "$rollingVersion`n")
Invoke-Native $miniExe @(
    (Join-Path $src 'host\genversion.lua'),
    (Join-Path $src 'luajit_rolling.h'),
    $generatedRelver,
    $generatedLuaJitHeader
)

$buildvmArch = Join-Path $hostOutput 'buildvm_arch.h'
Push-Location $src
try {
    Invoke-Native $miniExe @(
        (Join-Path $dynasm 'dynasm.lua'), '-LN',
        '-D', 'WIN', '-D', 'JIT', '-D', 'FFI', '-D', 'ENDIAN_LE',
        '-D', 'FPU', '-D', 'P64',
        '-o', $buildvmArch, 'vm_x64.dasc'
    )

    $buildvmSources = Get-ChildItem -LiteralPath (Join-Path $src 'host') -File -Filter 'buildvm*.c' |
        ForEach-Object FullName
    $buildvmObjectDir = "$hostOutput\"
    Invoke-Native $compiler ($commonHostFlags + @(
        "/I$hostOutput", "/I$output", "/I$src", "/I$dynasm", "/Fo$buildvmObjectDir"
    ) + $buildvmSources)

    $buildvmObjects = Get-ChildItem -LiteralPath $hostOutput -File -Filter 'buildvm*.obj' |
        ForEach-Object FullName
    $buildvmExe = Join-Path $hostOutput 'buildvm.exe'
    Invoke-Native $linker (@('/nologo', "/out:$buildvmExe") + $buildvmObjects + $hostLinkPaths)

    $libraries = @(
        'lib_base.c', 'lib_math.c', 'lib_bit.c', 'lib_string.c',
        'lib_table.c', 'lib_io.c', 'lib_os.c', 'lib_package.c',
        'lib_debug.c', 'lib_jit.c', 'lib_ffi.c', 'lib_buffer.c'
    )
    Invoke-Native $buildvmExe @('-m', 'peobj', '-o', (Join-Path $output 'lj_vm.obj'))
    Invoke-Native $buildvmExe (@('-m', 'bcdef', '-o', (Join-Path $output 'lj_bcdef.h')) + $libraries)
    Invoke-Native $buildvmExe (@('-m', 'ffdef', '-o', (Join-Path $output 'lj_ffdef.h')) + $libraries)
    Invoke-Native $buildvmExe (@('-m', 'libdef', '-o', (Join-Path $output 'lj_libdef.h')) + $libraries)
    Invoke-Native $buildvmExe (@('-m', 'recdef', '-o', (Join-Path $output 'lj_recdef.h')) + $libraries)
    Invoke-Native $buildvmExe (@('-m', 'vmdef', '-o', (Join-Path $jitOutput 'vmdef.lua')) + $libraries)
    Invoke-Native $buildvmExe @('-m', 'folddef', '-o', (Join-Path $output 'lj_folddef.h'), 'lj_opt_fold.c')
}
finally {
    Pop-Location
}
