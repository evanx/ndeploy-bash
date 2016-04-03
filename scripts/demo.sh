
unset ns
unset rediscli

ns='demo:ndeploy'
rediscli='redis-cli -n 13'

  ns=$ns rediscli=$rediscli bin/ndeploy tclear13
  ns=$ns rediscli=$rediscli bin/ndeploy pop 60 &
  ns=$ns rediscli=$rediscli bin/ndeploy tdeploy
