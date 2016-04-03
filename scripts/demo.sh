
set -e -u

unset ns
unset rediscli

ns='demo:ndeploy'
rediscli='redis-cli -n 13'

  ns=$ns rediscli=$rediscli bin/ndeploy tclear13
  sleep 1
  ns=$ns rediscli=$rediscli sh bin/ndeploy pop 10 &
  sleep 2
  deployDir=`ns=$ns rediscli=$rediscli sh bin/ndeploy tdeploy | tail -1`
  echo deployDir $deployDir
