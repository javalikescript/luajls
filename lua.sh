LUA_HOME=$1
export LUA_PATH="./?.lua;$LUA_HOME/?.lua"
export LUA_CPATH="$LUA_HOME/?.so"
##export PATH=$LUA_HOME:$PATH
shift
$LUA_HOME/lua $@
