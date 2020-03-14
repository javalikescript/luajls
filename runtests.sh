#!/bin/sh

errorcount=0
testcount=0
for f in tests/*/*.lua
do
  lua $f 1>/dev/null 2>/dev/null
  if test $? -ne 0
  then
    echo test $f in error:
    lua $f
    errorcount=`expr $errorcount + 1`
  fi
  testcount=`expr $testcount + 1`
done
if test $errorcount -ne 0
then
  echo $errorcount/$testcount files in error
else
  echo $testcount files pass
fi
