
### Service lifecycle management

An optional `serviceNamespace` configuration property e.g. `"demo:mpush"` is used for lifecycle management, and metrics.

This can be complemented with an optional `serviceRedis` URL, for the related keys. Otherwise they are stored in the default Redis database, i.e. the same instance as the target `:in` and `:out` queues.


#### Registration and renewal

At startup, the service will perform the following Redis commands to "register" itself:
- `incr :service:id` to obtain a unique service instance `id`
- `hmset :service:$id` to record `{host, pid, started}` et al
- `expire :service:$id $serviceExpire` but renew at an interval sufficiently less than `$serviceExpire`

For example, the `serviceExpire` is defaulted to 60 seconds, whereas the renewal period is 15 seconds.
```
INFO renew: started demo:mpush:service:9 15
```
So every 15 seconds, the TTL of the `:service:9` hashes will be renewed to 60 seconds. If the service stops running, then its hashes will automatically expire after 60 seconds.

```
redis-cli ttl demo:mpush:service:9
(integer) 54
```
where the `TTL` is 54 seconds, i.e. it was renewed 6 seconds ago.

```
redis-cli hkeys demo:mpush:service:9
1) "host"
2) "pid"
3) "started"
4) "renewed"
```
The `renewed` field above, is the heartbeat timestamp. Suffice it to say that if a service fails to renew its hashes, i.e. its heartbeat fails, then it must exit.


#### Namespace isolation

Naturally Redis data is dangerously "global" and mutable. We must mitigate this risk by distrusting the data. For example, the renewal processor validates that the `renewed` timestamp is unchanged from its previous setting.

Also, upon startup, a service must assert that its key does not exist.

Such checks should detect some misconfigurations and/or terrible bugs that expose the above-mentioned fragility, especially in deployment scenarios where many services use the same Redis instance.

<b>Ideally dedicated Redis instances should be used for different service namespaces.</b>


#### List of service ids

Additionally, we enlist registered ids as follows:
- `lpush :service:ids $id`
- `ltrim :service:ids 0 $serviceCapacity` to ensure that `:service:ids` is bounded.


As such we can get the latest service id:
```
redis-cli lrange demo:mpush:service:ids -1 -1
1) "9"
```

#### Service instance hashes

We inspect its hashes:
```
redis-cli hgetall demo:mpush:service:9
1) "host"
2) "eowyn"
3) "pid"
4) "32534"
5) "started"
6) "1459049541"
```

#### SIGTERM via pid

For example, we can `kill` the latest service instance as follows:
```
id=`redis-cli lrange demo:mpush:service:ids 0 0`
pid=`redis-cli hget demo:mpush:service:$id pid`
kill $pid
```
where we get the latest service id from the registration list, get its `pid` from its hashes, and kill that process.

We observe the logs:
```
INFO entry: SIGTERM
INFO Service: ended demo:mpush:service:9 { del: 1, lrem: 0 }
```
where the following cleanup commands are performed:
- `del :service:$id`
- `lrem :service:ids -1 $id` i.e. scanning from the tail


#### Remote shutdown via Redis

Services must monitor and ensure the existence of their key e.g. before each `brpoplpush` operation, and otherwise exit.

Therefore services can be shutdown via Redis by deleting their key:
```
redis-cli del demo:mpush:service:9
(integer) 0
```

In practice, we `brpoplpush :req :pending` e.g. so that crashes can be detected via `:pending` and perhaps even recovered e.g. in the event that some new version of the service instance is crashing after popping the message. In this scenario, we must detect the faulty instance, deregister it and schedule its shutdown e.g. `del` its service key.


#### Startup

At startup, the service instance must perform garbage-collection on behalf of other expired instances in the same `serviceNamespace.`

In particular, the service compacts the listed `:service:ids` as follows.
- iterate over `:service:ids`
- if any `:service:$id` does not exist, i.e. has expired or was deleted, then `lrem :service:ids -1 $id`

Therefore in the event of a service not shutting down gracefully, the stale `id` will be removed from the `:service:ids` list automatically at a later time.

Let's illustrate this process. Firstly, we iterate over `:service:ids`
```
redis-cli lrange demo:mpush:service:ids 0 -1
1) 9
```
For each `id` we check if key has expired (or was deleted):
```
redis-cli exists demo:mpush:service:9
(integer) 1
```
Finally, we remove any expired service ids from `:service:ids`
```
redis-cli lrem demo:mpush:service:ids -1 9
(integer) 1
```
which scans `:service:ids` from the tail.


#### Bug mitigation

Incidently, to mitigate the risk of services colliding in Redis due to undetected bugs and/or misconfiguration, one can configure a `serviceRedis` URL together with the `serviceNamespace`, and so provision dedicated Redis instances for various pods of services.

Further efforts will be taken, as follows:
- employ a `redisClient` mock for e2e tests
- introduce a `redisClient` safety wrapper e.g. with keyspace constraints


### Further reading

Service lifecycle management: https://github.com/evanx/mpush-redis/blob/master/service.md

Message lifecycle management, for timeouts etc: https://github.com/evanx/mpush-redis/blob/master/message.md

Metrics, for timeouts etc: https://github.com/evanx/mpush-redis/blob/master/metrics.md

Related projects and further plans: https://github.com/evanx/mpush-redis/blob/master/related.md


#### Redex

While this repo presents a standalone utility for a specific requirement, it is conceptually related to my "Redex" framework for Redis-based messaging - see https://github.com/evanx/redex.
