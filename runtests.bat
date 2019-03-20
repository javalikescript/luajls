@ECHO OFF
SETLOCAL

set JLS_LOGGER_LEVEL=

CALL :runall
GOTO :eof


set JLS_REQUIRES=socket,lfs
CALL :runall

set JLS_REQUIRES=luv
CALL :runall

set JLS_REQUIRES=

GOTO :eof


:runall
@for /f %%f in ('dir /b tests\*.lua') do @(
  echo Running %%f
  lua tests\%%f
)
GOTO :eof
