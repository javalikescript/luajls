#!/bin/sh

if test -z ${lua+x}
then
  lua=lua
  if which lua5.4 >/dev/null
  then
    lua=lua5.4
  fi
fi

#LUA_CPATH=none

#JLS_REQUIRES=\!luv
#JLS_REQUIRES=\!lfs,\!cjson,\!socket,\!linux,\!luachild,\!winapi

folders="base full"
if test "$LUA_CPATH" = "none"
then
  folders="base"
fi

$lua -v

#lua="$lua -lluacov"

### To generate coverage stats then report
## lua -lluacov tests/base/class.lua
## lua ../luaclibs/luacov/src/bin/luacov jls

errorcount=0
testcount=0
for d in $folders
do
  for f in tests/$d/*.lua
  do
    echo testing $f ...
    $lua $f 1>/dev/null 2>/dev/null
    if test $? -ne 0
    then
      echo test $f in error:
      $lua $f
      errorcount=`expr $errorcount + 1`
    fi
    testcount=`expr $testcount + 1`
  done
  echo test dir $d completed $errorcount/$testcount files in error
done
if test $errorcount -ne 0
then
  echo $errorcount/$testcount files in error
else
  echo $testcount files pass
fi
rm .jls.*.tmp
