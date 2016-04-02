
import assert from 'assert';

function format(type, options) {
   return type + ': ' + options.toString();
}

module.exports = {
   assert(value, name) {
      assert(value, name);
      return value;
   },
   assertString(value, name) {
      assert(value, name);
      assert(typeof value === 'string', name);
      return value;
   },
   assertString(value, name) {
      assert(value, name);
      assert(typeof value === 'string', name);
      return value;
   },
   assertInteger(value, name) {
      assert(value, name);
      assert(parseInt(value) === value, name);
      return value;
   },
   assertIntegerMax(value, name, max) {
      if (!max) {
         max = Invariants.props[name].max;
      }
      assert(value, {name, value});
      assert(Number.isInteger(value), format('integer', {name, value}));
      assert(value <= max, format('max', {name, value, max}));
      return value;
   },
   assertIntegerMin(value, name, min) {
      if (!min) {
         min = Invariants.props[name].min;
      }
      assert(value, {name, value});
      assert(Number.isInteger(value), format('integer', {name, value}));
      assert(value >= min, format('min', {name, value, min}));
      return value;
   },
   assertStringArray(value, name) {
      Asserts.assertArray(value, name);
      value.forEach(item => {
         Asserts.assertString(item, name);
      });
      return value;
   },
   assertArray(value, name) {
      assert(value, name);
      assert(lodash.isArray(value), 'not array: ' + name);
      assert(!lodash.isEmpty(value), 'empty: ' + name);
      return value;
   }
};
