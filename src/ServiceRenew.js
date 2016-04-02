
const logger = Loggers.createLogger(module.filename);

export default class ServiceRenew {

   constructor(name) {
      this.name = 'renew';
   }

   async start(state) {
      Object.assign(this, state);
      assert(this.props.serviceRedis, 'serviceRedis');
      this.redisClient = service.createRedisClient(this.props.serviceRedis);
      Asserts.assertIntegerMin(this.props.serviceRenew, 'serviceRenew', 10);
      this.intervalId = setInterval(() => this.run(), this.props.serviceRenew*1000);
      logger.info('started', this.service.key, this.props.serviceRenew);
   }

   async end() {
      if (this.ended) {
         logger.warn('end: ended');
         return;
      }
      this.ended = true;
      if (this.intervalId) {
         clearInterval(this.intervalId);
      }
      if (this.redisClient) {
         await this.redisClient.quitAsync();
      }
   }

   async run() {
      if (this.ended || this.service.ended) {
         logger.warn('run: ended', this.ended, this.service.ended);
         return;
      }
      try {
         const [[time], exists, timestamp] = await this.redisClient.multiExecAsync(multi => {
            multi.time();
            multi.exists(this.service.key);
            multi.hget(this.service.key, 'renewed');
         });
         assert(time > 0, 'time');
         if (!exists) {
            throw `exists ${this.service.key} ${exists}`;
         }
         if (this.timestamp) {
            if (timestamp !== this.timestamp) {
               throw new Error(`renewed ${timestamp} ${this.timestamp}`);
            }
         }
         this.timestamp = time;
         const [expire, hset] = await this.redisClient.multiExecAsync(multi => {
            this.logger.debug('renew', this.service.key, this.timestamp, this.props.serviceExpire);
            multi.expire(this.service.key, this.props.serviceExpire);
            multi.hset(this.service.key, 'renewed', this.timestamp);
         });
         if (!expire) {
            throw `renew ${this.service.key}`;
         }
      } catch (err) {
         this.service.error(this, err);
      }
   }
}
