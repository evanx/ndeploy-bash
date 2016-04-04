#!/bin/bash

set -u -e


# env context

ns=${ns:=demo\:ndeploy}
rediscli=${rediscli:=redis-cli -n 13}


# commands

c0clear13() {
  echo $ns | grep -q '^demo:'
  ls -l $HOME/.ndeploy/demo-ndeploy
  rm -rf $HOME/.ndeploy/demo-ndeploy
  for key in `redis-cli -n 13 keys "$ns:*"`
  do
    echo del $key
    $rediscli del $key
  done
}


# command

echo "rediscli: $rediscli"
echo "args: $@"

if [ $# -ge 1 ]
then
  command=$1
  shift
  c$#$command $@
fi
