const sysPath = require('path');
const fs = require('fs');
const detective = require('detective');
const browserResolve = require('browser-resolve');
const requireDefinition = require('commonjs-require-definition');
const each = require('async-each');
const os = require('os');

const isWindows = os.platform() === 'win32';
const separator = sysPath.sep || (isWindows ? '\\' : '/');

const shims = [
  'assert',
  'buffer',
  'child_process',
  'cluster',
  'crypto',
  'dgram',
  'dns',
  'events',
  'fs',
  'http',
  'https',
  'net',
  'os',
  'path',
  'punycode',
  'querystring',
  'readline',
  'repl',
  'string_decoder',
  'tls',
  'tty',
  'url',
  'util',
  'vm',
  'zlib'
];

const readFile = function(path, callback) {
  fs.readFile(path, {encoding: 'utf8'}, callback);
};

const nlre = /\n/g;

const newlinesIn = function(src) {
  var newlines;
  if (!src) {
    return 0;
  }
  newlines = src.match(nlre);
  if (newlines) {
    return newlines.length;
  } else {
    return 0;
  }
};

const getModuleRootPath = function(path) {
  var index, split;
  split = path.split(separator);
  index = split.lastIndexOf('node_modules');
  return split.slice(0, index + 2).join(separator);
};

const getModuleRootName = function(path) {
  var index, split;
  split = path.split(separator);
  index = split.lastIndexOf('node_modules');
  return split[index + 1];
};

const getHeader = function(moduleName) {
  return "require.register('" + moduleName + "', function (exp, req, mod) {\nmod.exports = (function e(t,n,r){function s(o,u){if(!n[o]){if(!t[o]){var a=typeof require==\"function\"&&require;if(!u&&a)return a(o,!0);if(i)return i(o,!0);var f=new Error(\"Cannot find module '\"+o+\"'\");throw f.code=\"MODULE_NOT_FOUND\",f}var l=n[o]={exports:{}};t[o][0].call(l.exports,function(e){var n=t[o][1][e];return s(n?n:e)},l,l.exports,e,t,n,r)}return n[o].exports}var i=typeof require==\"function\"&&require;for(var o=0;o<r.length;o++)s(r[o]);return s}) ({";
};

const readFileAndProcess = function(filePath, json, paths, rollback, allFiles, stop, done, loadDeps, pid) {
  return readFile(filePath, function(err, src) {
    var deps, getResult, item, itemHandler, resolved;
    if (err && rollback) {
      return stop(err);
    }
    deps = detective(src);
    resolved = {};
    item = {
      id: filePath,
      filename: filePath,
      paths: paths,
      "package": json
    };
    getResult = function() {
      return {
        id: filePath,
        source: src,
        deps: resolved,
        file: filePath
      };
    };
    if (deps.length === 0) {
      allFiles[filePath] = getResult();
      return done();
    }
    itemHandler = function(dep, cb) {
      return browserResolve(dep, item, function(err, fullPath) {
        if (err) {
          return cb(err);
        }
        resolved[dep] = fullPath;
        return cb(null, fullPath);
      });
    };
    each(deps, itemHandler, function(err, fullPathDeps) {
      if (err) {
        if (rollback) {
          return stop(null, '');
        } else {
          return stop(err);
        }
      }
      allFiles[filePath] = getResult();
      return fullPathDeps.filter(function(filePath) {
        return filePath;
      }).forEach(function(filePath) {
        return loadDeps(filePath, pid);
      });
    });
  });
};

const packDeps = function(modulePath, header, deps, ignoreRequireDefinition) {
  var entries, str, stringDeps;
  entries = [];
  stringDeps = deps.map(function(dep) {
    if (dep.entry && dep.order) {
      entries[dep.order] = dep.id;
    } else if (dep.entry) {
      entries.push(row.id);
    }
    deps = Object.keys(dep.deps || {}).sort().map(function(key) {
      return (JSON.stringify(key)) + ":" + (JSON.stringify(dep.deps[key]));
    });
    return [JSON.stringify(dep.id), ':[', 'function(require,module,exports){\n', dep.source, '\n},', "{ " + (deps.join(',')) + " }", ']'].join('');
  });
  entries = entries.filter(function(x) {
    return x;
  });
  str = '';
  if (!ignoreRequireDefinition) {
    str += requireDefinition;
  }
  str += header += stringDeps.join(',');
  str += '},{},' + JSON.stringify(entries) + (")('" + modulePath + "'); }) \n ");
  return str;
};

const loadFile = function(filePath, opts, callback) {
  var allFiles, entryModuleFilePath, loadDeps, paths, ref, stop, stopped, streams;
  allFiles = {};
  streams = {};
  stopped = false;
  if (typeof opts === 'function') {
    callback = opts;
    opts = null;
  }
  if (opts == null) {
    opts = {};
  }
  if (opts.paths == null) {
    opts.paths = ((ref = process.env.NODE_PATH) != null ? ref.split(':') : void 0) || [];
  }
  if (opts.basedir == null) {
    opts.basedir = process.cwd();
  }
  if (Array.isArray(opts.shims)) {
    shims = shims.concat(opts.shims);
  }
  paths = opts.paths.map(function(path) {
    return sysPath.resolve(opts.basedir, path);
  });
  filePath = sysPath.resolve(opts.basedir, filePath);
  entryModuleFilePath = filePath;
  stop = function(error, data) {
    stopped = true;
    return callback(error, data);
  };
  loadDeps = function(filePath, parentId) {
    var depRootPath, done, error, error1, json, pid;
    if (stopped) {
      return;
    }
    depRootPath = opts.rootPath || getModuleRootPath(filePath);
    pid = Date.now() + Math.round(Math.random() * 1000000);
    streams[pid] = false;
    if (parentId) {
      delete streams[parentId];
    }
    done = function() {
      var deps, header, packed;
      delete streams[pid];
      if (Object.keys(streams).length !== 0) {
        return;
      }
      deps = Object.keys(allFiles).map(function(key) {
        return allFiles[key];
      });
      header = opts.header || getHeader(opts.name || getModuleRootName(entryModuleFilePath));
      if (isWindows) {
        entryModuleFilePath = entryModuleFilePath.replace(/\\/g, '\\\\');
      }
      packed = packDeps(entryModuleFilePath, header, deps, opts.ignoreRequireDefinition);
      return callback(null, packed);
    };
    try {
      json = require(sysPath.join(depRootPath, 'package.json'));
    } catch (error1) {
      error = error1;
      return done();
    }
    if (allFiles[filePath]) {
      return done();
    }
    return readFileAndProcess(filePath, json, paths, opts.rollback, allFiles, stop, done, loadDeps, pid);
  };
  return loadDeps(filePath);
};

module.exports = loadFile;
