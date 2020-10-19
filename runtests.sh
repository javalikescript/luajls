#!/bin/sh

lua=lua
if which lua5.4 >/dev/null
then
  lua=lua5.4
fi

#export JLS_REQUIRES=!luv

$lua -v

errorcount=0
testcount=0
for d in base full
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
