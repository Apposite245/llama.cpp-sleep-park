@echo off
rem Builds llama-server with CUDA from a llama.cpp b11701 checkout with sleep-park.patch applied.
rem Usage: build-windows.cmd <path to the llama.cpp checkout>
rem CUDA 13.0 does not accept the VS 2026 (v145) compiler, hence -vcvars_ver=14.44 (the v143 toolset).

set "VCVARS=C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
set "CUDA_PATH=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.0"
rem 120 = RTX 50-series; e.g. 89 for RTX 40-series, 86 for RTX 30-series
set "CUDA_ARCH=120"

if "%~1"=="" (echo usage: %~nx0 ^<llama.cpp checkout^> & exit /b 1)
call "%VCVARS%" -vcvars_ver=14.44 >nul || exit /b 1
set "PATH=%CUDA_PATH%\bin;%PATH%"
cd /d "%~1" || exit /b 1
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=%CUDA_ARCH% ^
  -DLLAMA_CURL=OFF -DLLAMA_BUILD_TESTS=OFF -DCMAKE_CUDA_COMPILER="%CUDA_PATH%\bin\nvcc.exe" || exit /b 1
cmake --build build --target llama-server -j || exit /b 1
echo Built: %CD%\build\bin\llama-server.exe
