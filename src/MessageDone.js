
export default class MessageDone {

   constructor(name) {
      this.name = name;
   }

   async start(state) {
      Object.assign(this, state);
      this.redisNamespace = Asserts.assert(this.props.serviceNamespace, 'redisNamespace');
      this.redisClient = service.createRedisClient(this.props.serviceRedis);
      this.runPromise = this.run();
   }

   async end() {
      return this.runPromise;
   }

   async run() {
      this.logger.info('run');
      while (!this.ended && !this.service.ended) {
         try {
            await this.service.validate();
            await this.popDone();
         } catch (err) {
            this.service.error(this, err);
            break;
         }
      }
      this.ended = true;
      return this.redisClient.quitAsync();
   }

   async popDone() {
      const [pop, llen, [timestampString]] = await this.redisClient.multiExecAsync(multi => {
         multi.brpop(this.props.done, this.props.popTimeout);
         multi.llen(this.props.done);
         multi.time();
      });
      const timestamp = Invariants.parseInt(timestampString);
      if (!pop) {
         await this.service.delay(500);
      } else {
         const id = pop[1];
         const meta = await this.redisClient.hgetallAsync(this.redisKey(id));
         this.logger.debug('brpop', this.props.done, id, llen, timestamp, meta);
         if (!meta) {
            this.components.metrics.count('done:expired', id);
            this.components.metrics.histo('done', 1, id);
            return this.popDone();
         }
         const interval = this.props.messageTimeout;
         let timeout;
         let normalizedValue;
         if (!meta.deadline) {
            logger.warn('deadline', Object.keys(meta));
         } else {
            timeout = timestamp - meta.timestamp;
            normalizedValue = Math.min(1, timeout/this.props.messageTimeout);
            this.components.metrics.sum('done', timeout, id);
            this.components.metrics.histo('done', normalizedValue, id);
            this.logger.info('removed', {id, meta, timeout, normalizedValue});
         }
         const [del, lrem] = await this.redisClient.multiExecAsync(multi => {
            multi.del(this.redisKey(id));
            multi.lrem(this.redisKey('ids'), -1, id);
         });
         this.logger.info('removed', {id, meta, timeout, normalizedValue}, {del, lrem});
      }
   }

   redisKey(...values) {
      return [this.redisNamespace, 'message', ...values].join(':');
   }
}
