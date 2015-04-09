sysPath = require 'path'
fs = require 'fs'
detective = require 'detective'
browserResolve = require 'browser-resolve'
each = require 'async-each'

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
  fs.readFile filePath, {encoding: 'utf8'}, callback

requireDefinition = fs.readFileSync sysPath.join(__dirname, '../helpers/require.js'), 'utf8'

getModuleRootPath = (path) ->
  split = path.split('/')
  index = split.lastIndexOf('node_modules')
  split.slice(0, (index + 2)).join('/')

getModuleRootName = (path) ->
  split = path.split('/')
  index = split.lastIndexOf('node_modules')
  split[index + 1]

load = (filePath, opts, callback) ->
  callback = opts if typeof opts is 'function'
  allFiles = {}
  opts ?= {}
  streams = {}
  stopped = false
  shims = shims.concat(opts.shims) if opts.shims
  basedir = opts.basedir or process.cwd()
  paths = (opts.paths or process.env.NODE_PATH?.split(':') or [])
    .map (path) => sysPath.resolve(basedir, path)
  filePath = sysPath.resolve basedir, filePath

  tryToPack = ->
    if Object.keys(streams).length is 0
      packDeps null, Object.keys(allFiles).map (key) -> allFiles[key]

  stop = (error, data) ->
    stopped = true
    callback(error, data)

  loadDeps = (filePath, parid) ->
    console.log 'loadDeps', filePath
    return if stopped
    modulePath = opts.rootPath or getModuleRootPath(filePath)
    pid = Math.round(Math.random() * 1000000)
    streams[pid] = false
    delete streams[parid] if parid

    done = ->
      delete streams[pid]
      tryToPack()

    jsonPath = sysPath.join modulePath, 'package.json'

    try
      json = require jsonPath
    catch error
      return done()


    if allFiles[filePath]
      console.log 'Stopped', filePath
      return done()

    readFile filePath, (err, src) ->
      if err
        return stop(err) if opts.rollback
      console.log 'Read', filePath
      deps = detective(src)
      resolved = {}
      item =
        id: filePath
        filename: filePath
        paths: paths
        package: json

      getResult = ->
        id: filePath
        source: src
        deps: resolved
        file: filePath

      if deps.length is 0
        allFiles[filePath] = getResult()
        done()
      else
        itemHandler = (dep, cb) ->
          browserResolve dep, item, (err, fullPath) ->
            return cb(err) if err
            resolved[dep] = fullPath
            cb null, fullPath

        each deps, itemHandler, (err, fullPathDeps) ->
          if err
            if opts.rollback
              return stop(null, '')
            else
              return stop(err)
          allFiles[filePath] = getResult()
          fullPathDeps
          .filter (filePath) -> filePath
          .forEach (filePath) ->
            console.log 'each loadDeps', filePath
            loadDeps filePath, pid

  moduleName = opts.name or getModuleRootName(filePath)
  modulePath = filePath
  loadDeps(filePath)

  newlinesIn = (src) ->
    return 0 if !src
    newlines = src.match(/\n/g)
    if newlines then newlines.length else 0

  header = """
    require.register('#{moduleName}', function (exp, req, mod) {
    mod.exports = (function e(t,n,r){function s(o,u){if(!n[o]){if(!t[o]){var a=typeof require=="function"&&require;if(!u&&a)return a(o,!0);if(i)return i(o,!0);var f=new Error("Cannot find module '"+o+"'");throw f.code="MODULE_NOT_FOUND",f}var l=n[o]={exports:{}};t[o][0].call(l.exports,function(e){var n=t[o][1][e];return s(n?n:e)},l,l.exports,e,t,n,r)}return n[o].exports}var i=typeof require=="function"&&require;for(var o=0;o<r.length;o++)s(r[o]);return s}) ({
  """

  packDeps = (err, deps) ->
    console.log 'packDeps', deps
    header = opts.header or header
    entries = []
    stringDeps = deps.map (dep) ->
      if dep.entry and dep.order
        entries[dep.order] = dep.id
      else if dep.entry
        entries.push row.id
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
    str += requireDefinition if not opts.ignoreRequireDefinition
    str += header += stringDeps.join(',')
    str += '},{},' + JSON.stringify(entries) + ")('#{modulePath}'); }) \n "
    callback(null, str)

  return

module.exports = load
