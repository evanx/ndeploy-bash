
# mpush-redis

Note: the correct repo is: https://github.com/evanx/mpush-redis

This is a simple Redis-based message-parallelizing microservice. It supports a persistent pubsub setup via Redis lists, e.g. to support parallel task queues.

It is built for NodeJS, using the Babel transpiler to support async/await etc.

In practice, some "publisher" pushes a message onto a Redis list. <b>This service pops those messages, and pushes each message onto multiple lists, one for each subscriber.</b> Each subscriber pops messages from their own dedicated Redis list.

Clearly if a subscriber is offline, its incoming messages are "persistent" since they accumulate in Redis, and are available when the subscriber comes online again.

Incidently, a "subscriber" could be comprised of redundant microservices consuming the same subscription list. Such a system offers resilience and scalability. Clearly the service must be "stateless" in this case, e.g. where its state is externalized (and shared) using Redis.


### Status

UNSTABLE

This service will be put into production in the coming weeks, and thereafter I will tag a "stable" release.


### Implementation

This microservice is performs the following Redis operations.

- `brpoplpush` a message from a "publication" list, into a "pending" list.
- `lpush` the message to multiple "subscription" lists.
- Finally, remove the message from the "pending" list.

These operations are performed atomically, via Redis `multi.`

Herewith a simplified code snippet for illustration:
```javascript
   const message = await this.redisClient.brpoplpushAsync(this.props.in,
      this.props.pending, this.props.popTimeout);
   if (message) {
      const multi = this.redisClient.multi();
      this.props.out.forEach(out => multi.lpush(out, message));
      multi.lrem(this.props.pending, -1, message);
      await multi.execAsync();
   }
```
where we use `bluebird.promisifyAll` which mixes in async functions e.g. `execAsync` et al.

The blocking pop operation has a configured `popTimeout.` It is performed in a loop, until the service is "ended."

Note that the service will shutdown gracefully e.g. in the event of a `SIGTERM` signal. However, it must wait for the blocking operation to complete. Therefore `popTimeout` is the lower-bound of the worse-case shutdown duration.


### Installation

```shell
git clone https://github.com/evanx/mpush-redis
cd mpush-redis
npm install
```
Let's run the demo.
```shell
npm run demo
```
We see the demo configuration in the logs.
```shell
INFO App: config {
      redis: 'redis://localhost:6379/0',
      in: 'demo:mpush:in',
      pending: 'demo:mpush:pending',
      popTimeout: 10,
      out: [ 'demo:mpush:out0', 'demo:mpush:out1' ]
```

#### Blocking pop

From the logs, we deduce that the service performs the following command.

```
brpoplpush demo:mpush:in demo:mpush:pending 5
```
where the blocking pop operation has a configured timeout of 5 seconds (repeated in a infinite loop).

Note that this time determines the duration of a graceful shutdown, because we can only quit when this operation yields.

When the pop yields a message, this service must push this message into the parallel output queues.


#### Publish a message

Let's manually test this by pushing an incoming message into `:in`

```shell
redis-cli lpush demo:mpush:in one
(integer) 1
```

From the logs, we deduce that the service performs the following Redis commands.
```
lpush demo:mpush:out0 one
lpush demo:mpush:out1 one
```


#### Check subscription queues

We check that the message is moved to the parallel output queues.
```shell
redis-cli lrange demo:mpush:out0 0 -1
1) "one"
```

```shell
redis-cli lrange demo:mpush:out1 0 -1
1) "one"
```


### Configuration

Specify the configuration file via the `propsFile` environment variable.

```shell
propsFile=~/config/mpush-redis.js npm start
```

The specified config file is loaded via `require()` and so can be a `.js` or a `.json` file.

For example the following configuration specifies a `serviceRedis` and `serviceNamespace` to enable "advanced" features e.g. service registration, message timeouts, and other metrics.

```javascript
module.exports = {
   redis: 'redis://localhost:6379/0',
   serviceRedis: 'redis://localhost:6379/1',
   serviceNamespace: 'demo:mpush',
   popTimeout: 10,
   in: 'demo:mpush:in',
   pending: 'demo:mpush:pending',
   out: ['demo:mpush:out0', 'demo:mpush:out1'],
   done: 'demo:mpush:done'
};
```

#### Default props

Default values for props are reported in the logs as follows:
```
INFO Service:
    defaultProps {
      serviceExpire: 60,
      serviceRenew: 15,
      serviceCapacity: 10,
      messageExpire: 60,
      messageTimeout: 10,
      messageCapacity: 1000 }
```

Note that the `service*` and `message*` props are only required if the `serviceNamespace` is set.


### Further reading

Service lifecycle management: https://github.com/evanx/mpush-redis/blob/master/service.md

Message lifecycle management, for timeouts etc: https://github.com/evanx/mpush-redis/blob/master/message.md

Metrics, for timeouts etc: https://github.com/evanx/mpush-redis/blob/master/metrics.md

Related projects and further plans: https://github.com/evanx/mpush-redis/blob/master/related.md


#### Redex

While this repo presents a standalone utility for a specific requirement, it is conceptually related to my "Redex" framework for Redis-based messaging: https://github.com/evanx/redex
