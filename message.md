
### Message tracking for timeouts and retry

An optional `serviceNamespace` configuration property e.g. `"demo:mpush"` is used for message lifecycle management, as well as service lifecycle management and metrics.

This can be complemented with an optional `serviceRedis` URL, for the related keys. Otherwise they are stored in the default Redis database, i.e. the same instance as the target `:in` and `:out` queues.

A similar mechanism as that described for tracking services, is used for tracking messages, as follows:
- `incr :message:id` to obtain a sequential unique message `$id`
- `exists :message:$id` to check that the message key does not exist.
- `hmset :message:$id {fields}` for meta info
- `expire :message:$id $messageExpire` for automatic "garbage-collection"
- `lpush :message:ids $id` to register the new `$id`

Before we push a message, let's check the current sequential `:message:id`
```
redis-cli get demo:mpush:message:id
1) "2"
```
So the next message will be assigned an `id` of `3.`

Let's push a message, namely the number `12345.`
```
redis-cli lpush demo:mpush:in 12345
```

We check the latest message id:
```
redis-cli lrange demo:mpush:message:ids 0 -1
1) 3
```

And the `:message:$id` hashes:
```
redis-cli hgetall demo:mpush:message:3
1) "timestamp"
2) "1459166173"
3) "xid"
4) "123456"
5) "deadline"
6) "1459166183"
7) "service"
8) "1"
```

We record the "deadline" time calculated as `timestamp + timeout.` Suffice it to say that replica instances might have different timeouts, e.g. during rolling reconfigurations.


#### xid

We determine the `xid` as follows:
```javascript
async registerMessage(message) {
   const id = await this.redisClient.incrAsync(this.redisKey('id'));
   logger.debug('registerMessage', id);
   let xid;
   let xidHashes = {id};
   if (/^[0-9]+$/.test(message)) {
      xid = message;
      xidHashes.type = 'number';
   } else if (message.meta && message.meta.id) {
      xid = message.meta.id;
      xidHashes.type = 'meta';
   } else {
      xid = this.service.sha1(message);
      xidHashes.type = 'sha1';
   }
```
where `xid` is the extracted/intrinsic id of the message as follows:
- if the message itself is a number, then take this as the `xid`
- otherwise `message.meta.id` if this exists
- failing the above, the SHA1 hash of the message as the `xid`


We set a cross-referencing key for a subscriber worker to lookup the message id:
```
redis-cli hgetall demo:mpush:message:xid:12345
1) "id"
2) "3"
3) "type"
4) "number"
```
where the `type` indicates the incoming message was itself a number, i.e. `12345,` and so this is used for the `xid.`

The `:message:xid:$xid` key enables a subscriber worker to lookup the message `id` in order to push it into `:message:done.` Otherwise it will be counted as a timeout i.e. in the `:metrics:timeout` hashes:

```
redis-cli hget demo:mpush:metrics:timeout count
"3"
```

#### Timeout monitor

The `:message:$id` hashes include the `timestamp` of the message. This value is required to detect message timeouts.

The worker microservice which actually handles the message, pushes its id into a `:message:done` list. This list is monitored by our Redis microservice, to detect timeouts i.e. not "done" after the `messageTimeout` period.

Clearly `messageExpire` must be longer than `messageTimeout` to give our monitor sufficient time to detect timeouts.

The "timeout monitor" performs the following:
- `lrange :message:done 0 -1` to check processed messages
- `hget :message:$id timestamp` to get the original timestamp of a message
- `hincrby :metrics:done count 1`
- `hincrby :metrics:done sum $timeout`
- `hget:metrics:done max $max` and perhaps `hset`
- `lrem :message:ids -1 $id` to delist expired message ids

The `lrem` command is performed by the monitor when it detects expired ids, i.e. where the `:message:$id` hashes key does not exist e.g. because it was expired by Redis after the configured `$messageExpire` period.

#### Retry

IN PLANNING


### Further reading

Service lifecycle management: https://github.com/evanx/mpush-redis/blob/master/service.md

Message lifecycle management, for timeouts etc: https://github.com/evanx/mpush-redis/blob/master/message.md

Metrics, for timeouts etc: https://github.com/evanx/mpush-redis/blob/master/metrics.md

Related projects and further plans: https://github.com/evanx/mpush-redis/blob/master/related.md


#### Redex

While this repo presents a standalone utility for a specific requirement, it is conceptually related to my "Redex" framework for Redis-based messaging - see https://github.com/evanx/redex.
