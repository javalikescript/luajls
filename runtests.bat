@ECHO OFF
SETLOCAL

SET VERBOSE=no
SET JLS_REQUIRES=

:args
IF _%1==_ GOTO :main
SET ARG=%1
SHIFT
IF %ARG%==-v SET VERBOSE=yes
IF %ARG%==luv SET JLS_REQUIRES=!socket,!lfs
IF %ARG%==socket SET JLS_REQUIRES=!luv
GOTO :args

:main
SET JLS_LOGGER_LEVEL=
SET LUA=lua53
WHERE /Q %LUA%
IF ERRORLEVEL 1 SET LUA=lua
IF %VERBOSE%==yes (
  ECHO Lua is %LUA%
  ECHO   LUA_PATH=%LUA_PATH%
  ECHO   LUA_CPATH=%LUA_CPATH%
)

CALL :runall
GOTO :eof

SET JLS_REQUIRES=socket,lfs
CALL :runall

SET JLS_REQUIRES=luv
CALL :runall

SET JLS_REQUIRES=

GOTO :eof


:runall
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
  ECHO %TESTCOUNT% files pass
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
%LUA% tests\%TEST_DIR%\%TEST_FILE% 1>nul 2>nul
SET ERRLEV=%ERRORLEVEL%
SET /a TESTCOUNT+=1
IF %ERRLEV% NEQ 0 (
  SET /a ERRORCOUNT+=1
  ECHO /!\ test %TEST_FILE% in error:
  %LUA% tests\%TEST_DIR%\%TEST_FILE%
  ECHO.
)
GOTO :eof
