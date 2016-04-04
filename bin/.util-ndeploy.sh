
# logging

debug() {
   >&2 echo "DEBUG $loggerName - $*"
}

info() {
   >&2 echo "INFO  $loggerName - $*"
}

warn() {
   >&2 echo "WARN  $loggerName - $*"
}

error() {
   >&2 echo "ERROR $loggerName - $*"
}


# exit

abort() {
   echo "WARN abort: $*"
   exit 1
}


# grep utils

grepq() {
   [ $# -eq 1 ]
   grep -q "^${1}$"
}


# redis utils

redis() {
   $rediscli $*
}

redise() {
   expect=$1
   shift
   redisCommand="$@"
   if ! echo "$redisCommand" | grep -q " $ns:"
   then
      warn "$redisCommand"
      return 1
   fi
   reply=`$rediscli $redisCommand`
   if [ "$reply" != $expect ]
   then
      warn "$redisCommand - reply $reply - not $expect"
      return 2
   else
      return 0
   fi
}

redis0() {
   [ $# -gt 1 ]
   redise 0 $*
}

redis1() {
   [ $# -gt 1 ]
   redise 1 $*
}

# redis commands

expire() {
   info "expire $*"
   [ $# -eq 2 ]
   redis1 expire $*
}

exists() {
   [ $# -eq 1 ]
   redis1 exists $1
}

incr() {
   [ $# -eq 1 ]
   key=$1
   echo "$key" | grep -q "^$ns:\w[:a-z0-9]*$"
   seq=`$rediscli incr $key`
   echo "$seq" | grep '^[1-9][0-9]*$'
}

## hashes

hgetall() {
   [ $# -eq 1 ]
   key=$1
   echo "$key" | grep -q "^$ns:\w[:a-z0-9]*$"
   >&2 echo "DEBUG hgetall $key"
   >&2 $rediscli hgetall $key
}

hsetnx() {
   [ $# -eq 3 ]
   $rediscli hsetnx $* | grep -q '^1$'
}

hincrby() {
   [ $# -eq 3 ]
   reply=`$rediscli hincrby $*`
   debug "hincrby $* - $reply"
   echo $reply | grep '^[1-9][0-9]*$'
}

hgetd() {
   [ $# -eq 3 ]
   defaultValue=$1
   key=$2
   field=$3
   value=`$rediscli hget $key $field`
   if [ -z "$value" ]
   then
      echo "$defaultValue"
   else
      echo $value
   fi
}


## lists

lpush() {
   [ $# -eq 2 ]
   reply=`$rediscli lpush $*`
   debug "lpush $* - $reply"
   echo "$reply" | grep -q '^[1-9][0-9]*$'
}

brpoplpush() {
   [ $# -eq 3 ]
   popId=`$rediscli brpoplpush $*`
   debug "brpoplpush $* - $popId"
   echo $popId | grep '^[1-9][0-9]*$'
}

brpop() {
   [ $# -eq 2 ]
   debug "$rediscli brpop $*"
   popId=`$rediscli brpop $* | tail -1`
   debug "brpop $* - $popId"
   echo $popId | grep '^[1-9][0-9]*$'
}

lrem() {
   [ $# -eq 3 ]
   $rediscli lrem $* | grep -q '^[1-9][0-9]*$'
}

llen() {
   [ $# -eq 1 ]
   llen=`$rediscli llen $*`
   debug "llen $* - $llen"
   echo $llen | grep '^[1-9][0-9]*$'
}

## sets

sadd() {
   [ $# -eq 2 ]
   $rediscli sadd $* | grep -q '^[1-9][0-9]*$'
}


## app

nexists() {
   [ $# -eq 1 ]
   redis0 exists $1
}

count() {
   [ $# -ge 1 ]
   hincrby $ns::metric:$1 count 1 >/dev/null
}

incrid() {
   [ $# -eq 1 ]
   name=$1
   id=`incr $ns:$name:id`
   redis0 exists $ns:$name:$id
   echo $id
}
