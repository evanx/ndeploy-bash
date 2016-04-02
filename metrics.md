
## Metrics

An optional `serviceNamespace` configuration property e.g. `"demo:mpush"` is used for metrics.

This can be complemented with an optional `serviceRedis` URL, for the related keys. Otherwise they are stored in the default Redis database, i.e. the same instance as the target `:in` and `:out` queues.

### Implementation

We update `:metrics:$name` hashes with fields `{count, sum, max}.`

```
redis-cli hgetall demo:mpush:metrics:timeout
1) "count"
2) "3"
3) "sum"
4) "30"
5) "max"
6) "10"
```

The average time can be calculated by dividing `sum/count.`

We include histogram data e.g. counting the response times falling between 10% intervals of the timeout:
- `histo0` - `[0.0, 0.1)` inclusive of `0` but exclusive of `0.1` i.e. less than 10% of the timeout interval
- `histo10` - `[0.1, 0.2)` between 10% and 20%
- etc
- `histo90` - `[0.9, 1)` for messages less than the timeout, but equal or greater than 90% thereof
- `histo100` - `[1, infinity)` i.e. the number of values greater or equal to the `timeout` interval
where the value is normalized to a value in the range `[0, 1]` i.e. between 0 and 1, inclusive.

Here is a code sample:
```javascript
const [redisTime] = await this.redisClient.timeAsync();
const interval = parseInt(redisTime) - messageTimestamp;
await this.components.metrics.sum('timeout', interval, id);
await this.components.metrics.histo('timeout', Math.min(1, interval/this.props.messageTimeout), id);
```
where we count timeout durations exceeding the `messageTimeout` as having the maximum `normalizedValue` of `1.`

Let's check the timeout metrics:
```
redis-cli hgetall demo:mpush:metrics:timeout
1) "count"
2) "5"
3) "sum"
4) "50"
5) "max"
6) "10"
7) "histo100"
8) "5"
```
where since all timeout durations equal or exceed the `messageTimout` (10 seconds) we only have `histo100` counts (100%).

As mentioned before, the average is calculated as `sum/count`
```
ave=$[ 657/63 ]
10
```

In the case of response times (according to the `:message:done` notification queue), we see other histogram intervals e.g. `histo20` counts the number of response times between 20% to 30% of the `messageTimeout`
```
redis-cli hgetall demo:mpush:metrics:done
 1) "histo20"
 2) "2"
 3) "count"
 4) "6"
 5) "sum"
 6) "42"
 7) "max"
 8) "8"
 9) "histo70"
10) "2"
11) "histo60"
12) "2"
````

### Further reading

Service lifecycle management: https://github.com/evanx/mpush-redis/blob/master/service.md

Message lifecycle management, for timeouts etc: https://github.com/evanx/mpush-redis/blob/master/message.md

Metrics, for timeouts etc: https://github.com/evanx/mpush-redis/blob/master/metrics.md

Related projects and further plans: https://github.com/evanx/mpush-redis/blob/master/related.md


#### Redex

While this repo presents a standalone utility for a specific requirement, it is conceptually related to my "Redex" framework for Redis-based messaging - see https://github.com/evanx/redex.
