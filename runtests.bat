@ECHO OFF
SETLOCAL

set JLS_LOGGER_LEVEL=
set LUA=lua53

where /Q %LUA%
if ERRORLEVEL 1 set LUA=lua

CALL :runall
GOTO :eof


set JLS_REQUIRES=socket,lfs
CALL :runall

set JLS_REQUIRES=luv
CALL :runall

set JLS_REQUIRES=

GOTO :eof


:runall
echo Lua is %LUA% JLS_LOGGER_LEVEL=%JLS_LOGGER_LEVEL% JLS_REQUIRES=%JLS_REQUIRES%
@for /f %%f in ('dir /b tests\*.lua') do @(
  echo Running %%f
  %LUA% tests\%%f
)
GOTO :eof
