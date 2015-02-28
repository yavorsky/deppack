#Deppack

###Simple module to pack files with dependencies.

Example:

**index.js**
```javascript
var lastOf = require('./lastOf')

lastOf(3, 4)
```

**lastOf.js**
```javascript
var _ = require('underscore')

module.exports = function (array) {
  return _.last(array)
}
```

**write.js**
```javascript

var fs = require('fs');
var deppack = require('deppack');

deppack('index.js', {basedir: '.'}, function (err, data) {
  //data is index.js with loaded deps.
  fs.writeFileSync('bundle.js', data);
})

```
