LUA_HOME=$1
shift
export LUA_PATH="./?.lua;$LUA_HOME/?.lua"
export LUA_CPATH="$LUA_HOME/?.so"
#export LD_LIBRARY_PATH=$LUA_HOME
#export PATH=$LUA_HOME:$PATH
$LUA_HOME/lua $@
