sysPath = require 'path'
fs = require 'fs'
detective = require 'detective'
browserResolve = require 'browser-resolve'
requireDefinition = require 'commonjs-require-definition'
each = require 'async-each'

separator = sysPath.sep or (if isWindows then '\\' else '/')

shims = [
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
]

readFile = (path, callback) ->
  fs.readFile path, {encoding: 'utf8'}, callback

nlre = /\n/g
newlinesIn = (src) ->
  return 0 unless src
  newlines = src.match(nlre)
  if newlines then newlines.length else 0

getModuleRootPath = (path) ->
  split = path.split(separator)
  index = split.lastIndexOf('node_modules')
  split.slice(0, (index + 2)).join(separator)

getModuleRootName = (path) ->
  split = path.split(separator)
  index = split.lastIndexOf('node_modules')
  split[index + 1]

getHeader = (moduleName) ->
  """
  require.register('#{moduleName}', function (exp, req, mod) {
  mod.exports = (function e(t,n,r){function s(o,u){if(!n[o]){if(!t[o]){var a=typeof require=="function"&&require;if(!u&&a)return a(o,!0);if(i)return i(o,!0);var f=new Error("Cannot find module '"+o+"'");throw f.code="MODULE_NOT_FOUND",f}var l=n[o]={exports:{}};t[o][0].call(l.exports,function(e){var n=t[o][1][e];return s(n?n:e)},l,l.exports,e,t,n,r)}return n[o].exports}var i=typeof require=="function"&&require;for(var o=0;o<r.length;o++)s(r[o]);return s}) ({
  """

readFileAndProcess = (filePath, json, paths, rollback, allFiles, stop, done, loadDeps, pid) ->
  readFile filePath, (err, src) ->
    return stop err if err and rollback
    # console.log 'readFile', filePath
    deps = detective(src)
    resolved = {}
    item = {id: filePath, filename: filePath, paths, package: json}
    getResult = -> {id: filePath, source: src, deps: resolved, file: filePath}

    if deps.length is 0
      allFiles[filePath] = getResult()
      return done()

    itemHandler = (dep, cb) ->
      browserResolve dep, item, (err, fullPath) ->
        return cb(err) if err
        resolved[dep] = fullPath
        cb null, fullPath

    each deps, itemHandler, (err, fullPathDeps) ->
      if err
        if rollback
          return stop(null, '')
        else
          return stop(err)
      allFiles[filePath] = getResult()
      fullPathDeps
      .filter (filePath) -> filePath
      .forEach (filePath) ->
        # console.log 'each loadDeps', filePath
        loadDeps filePath, pid
    return

packDeps = (modulePath, header, deps, ignoreRequireDefinition) ->
  # console.log 'packDeps', deps
  entries = []
  stringDeps = deps.map (dep) ->
    if dep.entry and dep.order
      entries[dep.order] = dep.id
    else if dep.entry
      entries.push row.id # ???
    deps = Object.keys(dep.deps || {}).sort().map (key) ->
      "#{JSON.stringify(key)}:#{JSON.stringify(dep.deps[key])}"
    [
      JSON.stringify(dep.id)
      ':['
      'function(require,module,exports){\n'
      dep.source
      '\n},',
      "{ #{deps.join(',')} }"
      ']'
    ].join('')
  entries = entries.filter (x) -> x

  str = ''
  str += requireDefinition unless ignoreRequireDefinition
  str += header += stringDeps.join(',')
  str += '},{},' + JSON.stringify(entries) + ")('#{modulePath}'); }) \n "
  str


loadFile = (filePath, opts, callback) ->
  allFiles = {}
  streams = {}
  stopped = false

  if typeof opts is 'function'
    callback = opts
    opts = null

  opts ?= {}
  opts.paths ?= process.env.NODE_PATH?.split(':') or []
  opts.basedir ?= process.cwd()

  shims = shims.concat(opts.shims) if Array.isArray(opts.shims)
  paths = opts.paths.map (path) -> sysPath.resolve(opts.basedir, path)
  filePath = sysPath.resolve opts.basedir, filePath
  entryModuleFilePath = filePath

  stop = (error, data) ->
    stopped = true
    callback error, data

  loadDeps = (filePath, parentId) ->
    # console.log 'loadDeps', filePath
    return if stopped
    depRootPath = opts.rootPath or getModuleRootPath(filePath)
    pid = Date.now() + Math.round(Math.random() * 1000000)
    streams[pid] = false
    delete streams[parentId] if parentId
    done = ->
      # console.log 'done', filePath
      delete streams[pid]

      # Try to pack.
      return if Object.keys(streams).length isnt 0

      deps = Object.keys(allFiles).map (key) -> allFiles[key]
      header = opts.header or getHeader(opts.name or getModuleRootName entryModuleFilePath)
      packed = packDeps entryModuleFilePath, header, deps, opts.ignoreRequireDefinition
      callback null, packed

    try
      json = require sysPath.join depRootPath, 'package.json'
    catch error
      return done()
    return done() if allFiles[filePath]
    readFileAndProcess filePath, json, paths, opts.rollback, allFiles, stop, done, loadDeps, pid

  loadDeps filePath

module.exports = loadFile
