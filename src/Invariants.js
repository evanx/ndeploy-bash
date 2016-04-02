
// ES5 so can be used before Babel is registered

var that = {
   minTimestamp: 1459109145,
   minInterval: 1,
   maxInterval: 3600,
   defaultProps: {},
   validateProps: function(p) {
      Asserts.assertIntegerMax(p.serviceRenew, 'serviceRenew', p.serviceExpire - 5);
   },
   start: function(props) {
      Object.keys(props).forEach(function(key) {
         props[key].key = key;
         var defaultValue = props[key].defaultValue;
         if (defaultValue) {
            that.defaultProps[key] = defaultValue;
         }
      });
      console.log('defaultProps', that.defaultProps);
      that.validateProps(that.defaultProps);
      that.props = props;
   },
   validate(value, name) {
      assert.equal(typeof name, 'string', 'name');
      var meta = that.props[name];
      if (meta) {
         that.validateMeta(meta, value, name);
      }
      return value;
   },
   validateMeta(meta, value, name) {
      if (value === undefined) {
         if (!meta.optional) {
            throw new Error(`missing ${name}`);
         }
      }
      if (meta.min) {
         if (value >= meta.min) {
         } else {
            throw new Error(`${name} (${value}) min ${meta.min}`);
         }
      }
      if (meta.max) {
         if (value > meta.max) {
            throw new Error(`${name} (${value}) max ${meta.max}`);
         }
      }
      return value;
   },
   addTimestampInterval(timestamp, interval, name) {
      if (!interval || interval < that.minInterval || interval > that.maxInterval) {
         throw new Error(`${name} (${interval}) interval`);
      }
      return that.parseTimestamp(timestamp, name) + that.parseInt(interval);
   },
   validateTimestamp(value, name) {
      var timestamp = that.parseTimestamp(value, name);
      if (!timestamp) {
         throw new Error(`${name} timestamp`);
      }
      return timestamp;
   },
   validateMinExclusive(value, min, name) {
      if (value > min) {
         return value;
      } else {
         throw new Error(`${name} (${value}) min ${min}`);
      }
   },
   validateRangeInclusive(value, range, name) {
      if (value >= range[0] && value <= range[1]) {
         return value;
      } else {
         throw new Error(`${name} (${value}) range ${range}`);
      }
   },
   parseTimestamp(value, name) {
      var timestamp = that.parseInt(value, name);
      if (timestamp > 0 && timestamp < that.minTimestamp) {
         throw new Error(`${name} (${value}) timestamp`);
      }
      return timestamp;
   },
   parseInt(value, name) {
      if (value === 0) {
         return 0;
      } else if (!value) {
         return undefined;
      }
      var integerValue = parseInt(value);
      if (typeof value === 'string') {
      } else if (value !== integerValue) {
         throw new Error(`${name} (${value}) parseInt type ${typeof value}`);
      }
      if (integerValue === NaN) {
         throw new Error(`${name} (${value}) parseInt NaN`);
      }
      return integerValue;
   },
   validateInteger(value, name) {
      return that.validate(value, name);
   },
   validateIntegerMin(value, min, name) {
      that.validate(value, name);
      if (value >= min) {
      } else {
         throw new Error(`${name} (${value}) min ${min}`);
      }
      return value;
   },
   validateIntegerMin(value, min, name) {
      that.validate(value, name);
      if (value >= min) {
      } else {
         throw new Error(`${name} (${value}) min ${min}`);
      }
      return value;
   }

};

module.exports = that;
