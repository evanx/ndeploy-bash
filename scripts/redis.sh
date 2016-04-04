
ns='demo:ndeploy'
dbn=13
rediscli='redis-cli -n 13'

c1dbn() {
  dbn=$1
  echo "$dbn $ns $1"
  rediscli="redis-cli -n $dbn"
}

c0metrics() {
  for name in started
  do
    key="$ns:metric:$name"
    echo; echo "$key"
    $rediscli hgetall $key
  done
}

c0end() {
  id=`$rediscli lrange $ns:service:ids -1 -1`
  if [ -n "$id" ]
  then
    key="$ns:$id"
    echo "del $key"
    $rediscli del $key
  fi
}

c1kill() {
  id=$1
  pid=`$rediscli hget $ns:service:$id pid`
  if [ -n "$pid" ]
  then
    echo "kill $pid for $id"
    kill $pid
  fi
}

c0kill() {
  id=`$rediscli lrange $ns:service:ids 0 0`
  echo "$id" | grep -q '^[0-9]' && c1kill $id
}

c0killall() {
  id=`$rediscli lrange $ns:service:ids 0 0`
  echo "$id" | grep -q '^[0-9]' && c1kill $id
}

c1rhgetall() {
  name=$1
  id=`$rediscli lrange $ns:$name:ids -1 -1`
  if [ -z "$id" ]
  then
    echo "lrange $ns:$name:ids 0 -1" `$rediscli lrange $ns:$name:ids 0 -1`
  else
    key="$name:$id"
    echo "hgetall $ns:$key"
    $rediscli hgetall $ns:$key
  fi
}

c0ttl() {
  for key in `$rediscli keys "${ns}:*" | sort`
  do
    ttl=`$rediscli ttl $key | grep ^[0-9]`
    if [ -n "$ttl" ]
    then
      echo $key "-- ttl $ttl"
    else
      echo $key
    fi
  done
}

c0llen() {
   for list in service:ids pending ids
   do
     key="$ns:$list"
     echo "llen $key" `$rediscli llen $key` '--' `$rediscli lrange $key 0 99`
   done
}

c0state() {
  c0ttl
  c0llen
  c1rhgetall service
}

c0default() {
  c0state
}

command=default
if [ $# -ge 1 ]
then
  command=$1
  shift
fi
c$#$command $@
