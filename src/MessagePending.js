
export default class MessagePending {

   constructor(name) {
      this.name = name;
   }

   async start(state) {
      Object.assign(this, state);
      this.redisNamespace = Asserts.assert(this.props.serviceNamespace, 'serviceNamespace');
      this.redisClient = service.createRedisClient(this.props.redis);
      this.runPromise = this.run();
   }

   async end() {
      return this.runPromise;
   }

   async run() {
      this.logger.info('run');
      while (!this.ended && !this.service.ended) {
         try {
            if (!this.service.ended) {
               await this.service.validate();
               await this.peekPending();
            }
         } catch (err) {
            this.service.error(this, err);
            break;
         }
      }
      this.ended = true;
      return this.redisClient.quitAsync();
   }

   async peekPending() {
      const listKey = this.redisKey('ids');
      const [[timestampString], [id], length] = await this.redisClient.multiExecAsync(multi => {
         multi.time();
         multi.lrange(listKey, -1, -1);
         multi.llen(listKey);
      });
      if (!id) {
         await this.service.delay(800);
         return;
      }
      const timestamp = parseInt(timestampString);
      const meta = await this.redisClient.hgetallAsync(this.redisKey(id));
      if (!meta) {
         logger.debug('expired', this.redisKey(id));
         this.components.metrics.count('message:expired', id);
         await this.redisClient.lremAsync(listKey, -1, id);
         return;
      }
      const deadline = Invariants.parseTimestamp(meta.deadline, 'deadline');
      if (deadline > timestamp) {
      } else {
         Invariants.validateMinExclusive(this.props.messageTimeout, 0, 'messageTimeout');
         const messageTimestamp = Invariants.validateTimestamp(meta.timestamp, 'timestamp')
         const messageTimeout = this.props.messageTimeout;
         const timeout = timestamp - messageTimestamp;
         const normalizedValue = Math.min(1, timeout/messageTimeout);
         await this.components.metrics.sum('timeout', timeout, id);
         await this.components.metrics.histo('timeout', normalizedValue, id);
         const [del, lrem] = await this.redisClient.multiExecAsync(multi => {
            multi.del(this.redisKey(id));
            multi.lrem(listKey, -1, id);
         });
         this.logger.debug('removed', {id, meta, timestamp, messageTimeout, deadline, timestamp, timeout, normalizedValue, del, lrem});
         return;
      }
   }

   redisKey(...values) {
      return [this.redisNamespace, 'message', ...values].join(':');
   }
}
