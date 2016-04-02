
export default class MessageRegister {

   constructor(name) {
      this.name = name;
   }

   async start(state) {
      Object.assign(this, state);
      this.redisClient = service.createRedisClient(this.props.serviceRedis);
      this.redisNamespace = Asserts.assert(this.props.serviceNamespace, 'redisNamespace');
   }

   async end() {
      return this.redisClient.quitAsync();
   }

   async registerMessage(message) {
      logger.debug('registerMessage', this.redisKey('id'));
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
      logger.debug('registerMessage', id, xid);
      const [[timestampString], length, exists] = await this.redisClient.multiExecAsync(multi => {
         multi.time();
         multi.llen(this.redisKey('ids'));
         multi.exists(this.redisKey(id));
      });
      const timestamp = Invariants.parseTimestamp(timestampString);
      if (exists) {
         throw new Error('message exists: ' + this.redisKey(id));
      }
      if (length > this.props.messageCapacity) {
         this.components.metrics.max('messageCapacity', length, this.props.messageCapacity);
      } else {
         assert(this.props.messageExpire > 0, 'messageExpire');
         assert(this.props.messageTimeout > 0, 'messageTimeout');
         const multiResults = await this.redisClient.multiExecAsync(multi => {
            const deadline = Invariants.addTimestampInterval(timestamp, this.props.messageTimeout, 'deadline');
            const hashes = {timestamp, xid, deadline, service: this.service.id};
            logger.debug('register', id, hashes, xidHashes);
            multi.lpush(this.redisKey('ids'), id);
            multi.hmset(this.redisKey(id), hashes);
            multi.expire(this.redisKey(id), this.props.messageExpire);
            if (xid) {
               const key = this.redisKey('xid', xid);
               multi.hmset(key, xidHashes);
               multi.expire(key, this.props.messageExpire);
            }
         });
      }
   }

   redisKey(...values) {
      return [this.redisNamespace, 'message', ...values].join(':');
   }
}
