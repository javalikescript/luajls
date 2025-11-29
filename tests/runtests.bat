@ECHO OFF
SETLOCAL

SET ALL=no
SET BASE=no
SET VERBOSE=no
SET STDOUT=no
SET QUIET=no
SET JLS_REQUIRES=
SET JLS_LOGGER_LEVEL=
SET REPLAY_LOGGER_LEVEL=warn
SET COV=no
SET OPTS=

SET LUACOV_HOME=..\luaclibs\luacov
SET LUACOV_PATH=%LUA_PATH%;%LUACOV_HOME%\src\?.lua;..\datafile\?.lua
SET LUACOV_REPORT_OPTS=
SET LUACOV_REPORT_EXT=.out
SET LUA_PATH_BOOT=%LUA_PATH%

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
IF %ARG%==-c SET COV=yes
IF %ARG%==-l SET JLS_LOGGER_LEVEL=finest
IF %ARG%==base SET BASE=yes
IF %ARG%==luv SET JLS_REQUIRES=!socket,!lfs,!llthreads,!win32,!winapi,!luachild
IF %ARG%==noluv SET JLS_REQUIRES=!luv
IF %ARG%==nossl SET JLS_REQUIRES=!openssl
IF %ARG%==none SET JLS_REQUIRES=!buffer,!cjson,!lfs,!socket,!llthreads,!lpeg,!luv,!openssl,!webview,!win32,!winapi,!zlib,!luachild
GOTO :args

:main
SET LUA=lua54
WHERE /Q %LUA%
IF ERRORLEVEL 1 SET LUA=lua
IF %VERBOSE%==yes (
  ECHO Lua is %LUA%
  ECHO   LUA_PATH=%LUA_PATH%
  ECHO   LUA_CPATH=%LUA_CPATH%
)

IF %COV%==yes (
  IF EXIST %LUACOV_HOME% (
    ECHO Coverage enabled
    DEL /Q luacov.stats.out
    SET OPTS=-lluacov
    SET LUA_PATH=%LUACOV_PATH%
    %LUA% -e "require('datafile')" 2> NUL
    IF ERRORLEVEL 0 (
      SET LUACOV_REPORT_OPTS=-r html
      SET LUACOV_REPORT_EXT=.html
    ) ELSE (
      ECHO Coverage HTML report disabled, module datafile not available
    )
    SET LUA_PATH=%LUA_PATH_BOOT%
  ) ELSE (
    ECHO Luacov not available at %LUACOV_HOME%
    SET COV=no
  )
)

IF %ALL%==yes GOTO :runall
IF %BASE%==yes GOTO :runbase

CALL :runtests default
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
CALL :runtests nosocket
REM missing !zlib !openssl
SET JLS_REQUIRES=!luv,!lxp,!cjson,!buffer
CALL :runtests noluv
DEL .jls.*.tmp
SET JLS_LOGGER_LEVEL=finest
SET JLS_REQUIRES=
CALL :runtests logs
GOTO :eof

:runtests
IF %COV%==yes DEL /Q luacov.stats.out 1>NUL 2>NUL
IF %VERBOSE%==yes ECHO JLS_REQUIRES=%JLS_REQUIRES%
SET NAME=%1
SET TIMESTAMP=%DATE:~6,4%%DATE:~3,2%%DATE:~0,2%%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%
SET TIMESTAMP=%TIMESTAMP: =0%
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
IF %COV%==yes (
  ECHO Generate coverage report luacov.report.%NAME%.%TIMESTAMP%%LUACOV_REPORT_EXT%
  SET PUBLIC=%LUACOV_HOME%
  SET LUA_PATH=%LUACOV_PATH%
  %LUA% %LUACOV_HOME%/src/bin/luacov %LUACOV_REPORT_OPTS% jls
  SET LUA_PATH=%LUA_PATH_BOOT%
  REN luacov.report.out luacov.report.%NAME%.%TIMESTAMP%%LUACOV_REPORT_EXT%
  COPY luacov.report.%NAME%.%TIMESTAMP%%LUACOV_REPORT_EXT% luacov.report.%NAME%%LUACOV_REPORT_EXT%
)
del .jls.*.tmp
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
  %LUA% %OPTS% tests\%TEST_DIR%\%TEST_FILE%
) ELSE (
  %LUA% %OPTS% tests\%TEST_DIR%\%TEST_FILE% 1>NUL 2>NUL
)
SET ERRLEV=%ERRORLEVEL%
SET /a TESTCOUNT+=1
IF %ERRLEV% NEQ 0 (
  SET /a ERRORCOUNT+=1
  ECHO /!\ test %TEST_FILE% in error
  IF NOT %STDOUT%==yes (
    IF NOT %QUIET%==yes (
      SET CURRENT_LOGGER_LEVEL=%JLS_LOGGER_LEVEL%
      SET JLS_LOGGER_LEVEL=%REPLAY_LOGGER_LEVEL%
      %LUA% tests\%TEST_DIR%\%TEST_FILE%
      ECHO.
      SET JLS_LOGGER_LEVEL=%CURRENT_LOGGER_LEVEL%
    )
  )
)
GOTO :eof
