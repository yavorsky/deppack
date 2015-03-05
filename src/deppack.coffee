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

module.exports = load = (filePath, opts, callback) ->
  callback = opts if typeof opts is 'function'
  opts ?= {}
  allFiles = {}
  streams = {}
  stopped = false
  shims = shims.concat(opts.shims) if opts.shims
  basedir = opts.basedir or process.cwd()
  paths = (opts.paths or process.env.NODE_PATH?.split(':') or [])
    .map (path) => sysPath.resolve(basedir, path)
  filePath = sysPath.resolve basedir, filePath

  getModuleRootPath = (filePath) ->
    pathArray = filePath.split('/')
    rootIndex = pathArray.lastIndexOf('node_modules')
    pathArray.slice(0, (rootIndex + 2)).join('/')

  tryToPack = ->
    if Object.keys(streams).length is 0
      packDeps null, Object.keys(allFiles).map (key) -> allFiles[key]

  stop = (error, data) ->
    stopped = true
    callback(error, data)

  loadDeps = (filePath, parid) ->
    return if stopped
    modulePath = getModuleRootPath(filePath)
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

    fs.readFile filePath, {encoding: 'utf8'}, (err, src) ->
      if err
        return stop(err) if opts.rollback
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
          if dep in shims
            if opts.ignoreErrors
              cb()
            else
              cb(new Error("Module #{dep} is node.js shim. Use `rollback:true` in options to rollback root module or `ignoreErros: true` to load modules ignoring inaccessible modules."))
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
          fullPathDeps.forEach (filePath) ->
            loadDeps filePath, pid if filePath

  loadDeps(filePath)

  newlinesIn = (src) ->
    return 0 if !src
    newlines = src.match(/\n/g)
    if newlines then newlines.length else 0

  header = '''
    (function e(t,n,r){function s(o,u){if(!n[o]){if(!t[o]){var a=typeof require=="function"&&require;if(!u&&a)return a(o,!0);if(i)return i(o,!0);var f=new Error("Cannot find module '"+o+"'");throw f.code="MODULE_NOT_FOUND",f}var l=n[o]={exports:{}};t[o][0].call(l.exports,function(e){var n=t[o][1][e];return s(n?n:e)},l,l.exports,e,t,n,r)}return n[o].exports}var i=typeof require=="function"&&require;for(var o=0;o<r.length;o++)s(r[o]);return s}) ({
  '''

  packDeps = (err, deps) ->
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

    str = header += stringDeps.join(',')
    str += '},{},' + JSON.stringify(entries) + ');\n'
    callback(null, str)
