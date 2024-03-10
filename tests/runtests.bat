@ECHO OFF
SETLOCAL

SET ALL=no
SET BASE=no
SET VERBOSE=no
SET STDOUT=no
SET QUIET=no
SET JLS_REQUIRES=

:args
IF _%1==_ GOTO :main
SET ARG=%1
SHIFT
IF %ARG%==-v SET VERBOSE=yes
IF %ARG%==-o SET STDOUT=yes
IF %ARG%==-q SET QUIET=yes
IF %ARG%==-a SET ALL=yes
IF %ARG%==all SET ALL=yes
IF %ARG%==-b SET BASE=yes
IF %ARG%==base SET BASE=yes
IF %ARG%==luv SET JLS_REQUIRES=!socket,!lfs,!llthreads,!win32,!winapi,!luachild
IF %ARG%==noluv SET JLS_REQUIRES=!luv
IF %ARG%==nossl SET JLS_REQUIRES=!openssl
IF %ARG%==none SET JLS_REQUIRES=!buffer,!cjson,!lfs,!socket,!llthreads,!lpeg,!luv,!openssl,!webview,!win32,!winapi,!zlib,!luachild
GOTO :args

:main
SET JLS_LOGGER_LEVEL=
SET LUA=lua54
WHERE /Q %LUA%
IF ERRORLEVEL 1 SET LUA=lua
IF %VERBOSE%==yes (
  ECHO Lua is %LUA%
  ECHO   LUA_PATH=%LUA_PATH%
  ECHO   LUA_CPATH=%LUA_CPATH%
)

IF %ALL%==yes GOTO :runall
IF %BASE%==yes GOTO :runbase

CALL :runtests
GOTO :eof

:runbase
IF %VERBOSE%==yes ECHO JLS_REQUIRES=%JLS_REQUIRES%
SET TESTCOUNT=0
SET ERRORCOUNT=0
CALL :rundir base
IF %ERRORCOUNT% NEQ 0 (
  ECHO %ERRORCOUNT%/%TESTCOUNT% files in error
) ELSE (
  ECHO %TESTCOUNT% files passed
)
GOTO :eof

:runall
SET JLS_REQUIRES=!socket,!lfs
CALL :runtests
REM missing !zlib !openssl
SET JLS_REQUIRES=!luv,!lxp,!cjson
CALL :runtests
SET JLS_REQUIRES=
CALL :runtests
GOTO :eof

:runtests
IF %VERBOSE%==yes ECHO JLS_REQUIRES=%JLS_REQUIRES%
SET TESTCOUNT=0
SET ERRORCOUNT=0
SET LUA_CPATH_SAVED=%LUA_CPATH%
SET LUA_CPATH=
CALL :rundir base
SET LUA_CPATH=%LUA_CPATH_SAVED%
CALL :rundir full
IF %ERRORCOUNT% NEQ 0 (
  ECHO %ERRORCOUNT%/%TESTCOUNT% files in error
) ELSE (
  ECHO %TESTCOUNT% files passed
)
GOTO :eof

:rundir
SET TEST_DIR=%1
IF %VERBOSE%==yes ECHO %TEST_DIR%
FOR /f %%f in ('dir /b tests\%TEST_DIR%\*.lua') DO CALL :runtest %TEST_DIR% %%f
GOTO :eof

:runtest
SET TEST_DIR=%1
SET TEST_FILE=%2
IF %VERBOSE%==yes ECHO   %TEST_FILE%
IF %STDOUT%==yes (
  %LUA% tests\%TEST_DIR%\%TEST_FILE%
) ELSE (
  %LUA% tests\%TEST_DIR%\%TEST_FILE% 1>nul 2>nul
)
SET ERRLEV=%ERRORLEVEL%
SET /a TESTCOUNT+=1
IF %ERRLEV% NEQ 0 (
  SET /a ERRORCOUNT+=1
  ECHO /!\ test %TEST_FILE% in error
  IF NOT %STDOUT%==yes (
    IF NOT %QUIET%==yes (
      %LUA% tests\%TEST_DIR%\%TEST_FILE%
      ECHO.
    )
  )
)
GOTO :eof
