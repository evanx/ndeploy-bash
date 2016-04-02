
ns='demo:mpush'
dbn=1

c1dbn() {
  dbn=$1
  echo "$dbn $ns $1"
  rediscli="redis-cli -n $dbn"
}

c0flush() {
  $rediscli keys "$ns:*" | xargs -n1 $rediscli del
}

c0clear() {
  for list in service:ids message:ids in pending done out0 out1 
  do
    key="$ns:$list"
    echo "del $key" `$rediscli del $key`
  done
}

c0xid() {
  for key in `$rediscli keys "${ns}:message:xid:*" | sort`
  do
    echo; echo "$key"
    $rediscli hgetall $key
  done
}

c0metrics() {
  for key in `$rediscli keys "${ns}:metrics:*" | sort`
  do
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

c0done() {
  id=`$rediscli lrange $ns:message:ids -1 -1`
  if [ -n "$id" ]
  then
     $rediscli lpush "$ns:done" $id
  fi
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

c0state() {
  echo
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
  for list in service:ids message:ids in pending done out0 out1 
  do
    key="$ns:$list"
    echo "llen $key" `$rediscli llen $key` '--' `$rediscli lrange $key 0 99`
  done
  c1rhgetall service
  c1rhgetall message
}

c1push() {
  $rediscli lpush "$ns:in" $1
  sleep .2
  c0xid
  c0state
}

c0push() {
  c1push 12345
}

c0default() {
  $rediscli lpush "$ns:in" one
  $rediscli lpush "$ns:in" two
  sleep .1
  c0state
}

command=default
if [ $# -ge 2 ]
then
  dbn=$1
  shift
  c1dbn $dbn
  command=$1
  shift
  c$#$command $@
fi
