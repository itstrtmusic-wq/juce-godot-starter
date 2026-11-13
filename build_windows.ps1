param([ValidateSet("Debug", "Release", "RelWithDebInfo")][string]$Configuration = "Release")
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
foreach ($tool in @("cmake", "git", "python")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Install $tool and reopen PowerShell. See README.md."
    }
}
cmake -S . -B build/windows -G "Visual Studio 17 2022" -A x64
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed" }
cmake --build build/windows --config $Configuration --parallel 4
if ($LASTEXITCODE -ne 0) { throw "Build failed" }
ctest --test-dir build/windows -C $Configuration --output-on-failure
if ($LASTEXITCODE -ne 0) { throw "Tests failed" }
Write-Host "Ready: import demo/project.godot in Godot."
