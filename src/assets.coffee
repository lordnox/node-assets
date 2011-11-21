log = (key, val, error) ->
  color = if error then 'red' else 'cyan'
  console.error "  %s : ".white + "%s"[color], key, val

require 'colors'
fs              = require("fs")
url             = require("url")
{basename}      = require("path")
mkdirp          = require("mkdirp")
{join, dirname} = require("path")
imports         = {}

module.exports = (options) ->
  options     = options or {}
  force       = options.force
  debug       = options.debug
  src         = options.src or './private'
  dest        = options.dest or options.src or './public'
  compiler    = options.compiler

  throw new Error "node-assets() requires at least one compiler"      unless compiler

  # If we don't have an array, convert it
  if not (compiler instanceof Array)
    if typeof compiler is 'string' or compiler.compile
      compiler    = [compiler] 
    else
      compiler    = Object.keys(compiler).map (key) ->
        compiler[key]

  compiler    = compiler.map (compiler) ->
    if typeof compiler is 'string'
      throw new Error "node-assets() failed to find the compiler " + compiler unless module.exports.compiler[compiler]
      return module.exports.compiler[compiler]
    return compiler

  stack       = [] 


  compiler.forEach (compiler, key) ->
    config    = compiler.options || {}
    cache     = {}

    stack.push (path, next) ->
      regex = new RegExp('^(.*\.)' + compiler.dest + '$')
      return next() unless regex.test(path)
      
      destPath = join dest, path
      srcPath = join src, (path.replace regex, '$1') + compiler.source

      config.path  = srcPath 

      compile = ->

        log 'read', srcPath     if debug
        log 'write', destPath   if debug

        fs.readFile srcPath, "utf8", (err, input) ->
          return next err         if err

          compiler.compile input, config, (err, output) ->
            return next err       if err

            mkdirp dirname(destPath), 0700, (err) ->
              return next err     if err

              cache[srcPath] =
                output: output
                time: 100

              fs.writeFile destPath, output, "utf8", next
      
      return compile() if force ? options.force ? (not cache[srcPath]?)

      fs.stat srcPath, (err, srcStats) ->
        return next err           if err
        fs.stat destPath, (err, destStats) ->
          if err
            if "ENOENT" is err.code
              log "not found", destPath  if debug
              return compile()
            return next err
          return next() if destStats.mtime > srcStats.mtime
          log "modified", srcPath         if  debug
          compile()

  (req, res, next) ->
    return next()  if "GET" isnt req.method and "HEAD" isnt req.method

    path  = url.parse(req.url).pathname
    index = 0

    call  = (err, done) ->
      if err
        return next if "ENOENT" is err.code then null else err
      return next err if done or not (typeof stack[index] is 'function')
      fn      = stack[index]
      index  += 1

      fn.call req, path, call


    return call null

module.exports.compiler = {}


stylus = try require 'stylus' catch e then null
if stylus
  nib = try require 'nib' catch e then (-> ->)

  module.exports.compiler.stylus =
    source: 'styl'
    dest: 'css'
    compile: (input, config, fn) ->
      console.log config.path
      style = stylus(input)
        .set("filename", config.path)
        .set("compress", config.compress ? true)
        .set("debug", config.debug ? false)
        .set("firebug", false)
        .set("linenos", false)
      style.use(nib()).import('nib') if (config.nib ? true)
      style.render fn

checkImports = (path, fn) ->
  nodes = imports[path]
  return fn()  unless nodes
  return fn()  unless nodes.length
  pending = nodes.length
  changed = []
  nodes.forEach (imported) ->
    fs.stat imported.path, (err, stat) ->
      changed.push imported.path  if err or not imported.mtime or stat.mtime > imported.mtime
      --pending or fn(changed)


coffee = try require 'coffee-script' catch e then null
if coffee
  module.exports.compiler.coffee =
    source: 'coffee'
    dest: 'js'
    compile: (input, config, fn) ->
      try
        output = coffee.compile input
      catch err
        return fn err
      fn null, output