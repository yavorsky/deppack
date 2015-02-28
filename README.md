#Deppack

###Simple module to pack files with dependencies.

Example:

```javascript

var fs = require('fs');
var deppack = require('deppack');

deppack('index.js', {basedir: '.'}, function (err, data) {
  //data is index.js with loaded deps.
  fs.writeFileSync('bundle.js', data);
})

```
