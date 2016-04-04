#!/bin/bash

set -u -e

scriptDir=`dirname $0`

# help (listing commands)

if [ $# -eq 0 ]
then
   cat $0 | grep ^c[0-9] | sed 's/^c\([0-9]\)\(\w*\)() { [\W]*\s*\(.*\)$/\2 \1 \3/' | sort
   exit 0
fi


# env context

ns=${ns:=demo\:ndeploy}
rediscli=${rediscli:=redis-cli -n 13}

# server context

servicettl=${servicettl:=120}


# require utils

. $scriptDir/.util-ndeploy.sh

# init service

serviceId=`incrid service | tail -1`
serviceKey="$ns:service:$serviceId"
loggerName=$serviceKey
serviceDir=$HOME/.ndeploy/`echo $ns | tr ':' '-'`
count started $serviceId $$ $serviceDir
redis0 exists $serviceKey
hsetnx $serviceKey host `hostname -s`
hsetnx $serviceKey pid $$
hsetnx $serviceKey started `$rediscli time | head -1`
expire $serviceKey $servicettl
hgetall $serviceKey
mkdir -p $serviceDir && cd $serviceDir || exit 1


# service functions

c0daily() {
   echo 'not implemented'
}

c0hourly() {
   echo 'not implemented'
}

v1reqError() {
   id=$1
   error "pop: $*"
   count reqError $id
   $rediscli hset $ns:res:$id error reqError
   $rediscli lpush $ns:res $id
   $rediscli lrem $ns:req:pending -1 $id
   exit 9
}

pendingId=''

f0exit() {
   if [ -n "$pendingId" ]
   then
      v1reqError $pendingId
   fi
}

trap f0exit exit

c1loop() { # popTimeout
   popTimeout=$1
   while true
   do
      c1pop $popTimeout
      sleep 4
   done
}

popped() { # id
   id=$1
   count popped $id
   git=`$rediscli hget $ns:req:$id git | grep '^http\|^git@'`
   branch=`hgetd master $ns:req:$id branch`
   commit=`$rediscli hget $ns:req:$id commit`
   tag=`$rediscli hget $ns:req:$id tag`
   cd $serviceDir
   ls -lht
   deployDir="$serviceDir/$id"
   [ ! -d $deployDir ]
   sadd $ns:ids $id
   hsetnx $ns:res:$id deployDir $deployDir/$branch
   expire $ns:res:$id 900 # ttl sufficient for git clone and npm install
   echo "INFO deployDir $deployDir"
   mkdir -p $deployDir && cd $deployDir
   git clone $git -b $branch $branch
   cd $branch
   if [ -n "$commit" ]
   then
      echo "INFO git checkout $commit -- $git $branch"
      git checkout $commit
   elif [ -n "$tag" ]
   then
      echo "INFO git checkout tags/$tag -- $git $tag"
      git checkout tags/$tag
   fi
   hsetnx $ns:res:$id cloned `stat -c %Z $deployDir`
   if [ -f package.json ]
   then
      cat package.json
      npm --silent install
      hsetnx $ns:res:$id npmInstalled `stat -c %Z node_modules`
      count npmInstalled $id
   fi
   actualCommit=`git log | head -1 | cut -d' ' -f2`
   echo "INFO actualCommit $actualCommit"
   hsetnx $ns:res:$id actualCommit $actualCommit
   deployDir=`$rediscli hget $ns:res:$id deployDir`
   debug "OK res $id $deployDir"
}

c1pop() { # popTimeout
	popTimeout=$1
	expire $serviceKey $popTimeout
	redisCommand="brpoplpush $ns:req $ns:pending $popTimeout"
	id=`$rediscli $redisCommand | grep '^[1-9][0-9]*$'`
	debug "popped $id"
	[ -n $id ]
	pendingId=$id
	expire $ns:req:$id 10
	hgetall $ns:req:$id
	popped $id
	redis1 sadd $ns:res:ids $id
	redis1 persist $ns:res:$id
	hgetall $ns:res:$id
	lpush $ns:res $id
	pendingId=''
}

# command

info "rediscli: $rediscli"
info "args: $@"

if [ $# -ge 1 ]
then
   command=$1
   shift
   c$#$command $@
fi
