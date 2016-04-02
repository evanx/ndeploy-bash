
module.exports = {
   serviceExpire: {
      defaultValue: 60,
      min: 30,
   },
   serviceRenew: {
      defaultValue: 15,
      min: 5
   },
   serviceCapacity: {
      defaultValue: 10
   },
   messageExpire: {
      defaultValue: 60
   },
   messageTimeout: {
      defaultValue: 10
   },
   messageCapacity: {
      defaultValue: 1000
   },
   popTimeout: {
      max: 30
   }
};
