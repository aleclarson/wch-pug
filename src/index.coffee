assert = require 'assert'
noop = require 'noop'
path = require 'path'
pug = require 'pug2lua'
wch = require 'wch'

module.exports = (log) ->
  debug = log.debug 'wch-pug'

  shortPath = (path) ->
    path.replace process.env.HOME, '~'

  compile = (input, file) ->
    try mtime = fs.stat(file.dest).mtime.getTime()
    return if mtime and mtime > file.mtime_ms

    debug 'Transpiling:', shortPath file.path
    return file.compile input

  build = wch.pipeline()
    .read compile
    .save (file) -> file.dest
    .each (dest, file) ->
      wch.emit 'file:build', {file: file.path, dest}

  clear = wch.pipeline()
    .delete (file) -> file.dest
    .each (dest, file) ->
      wch.emit 'file:delete', {file: file.path, dest}

  pugRE = /\.pug$/
  pugExtsByLang =
    lua: '.lua'
    moon: '.lua'

  pugCompilers =
    lua: (code) -> pug.lua pug.ast code
    moon: (code) ->
      ast = pug.ast code
      await pug.transpile ast, {moon: true}
      pug.lua ast

  watchOptions =
    exts: ['pug', 'html', 'svg']

  methods:

    watch: (dir, opts) ->
      assert opts and typeof opts is 'object'
      assert typeof opts.dest is 'string'

      lang = opts.lang or 'lua'
      unless pugExt = pugExtsByLang[lang]
        throw Error 'Unknown language: ' + lang

      dest = path.resolve @path, opts.dest
      getDest = (file) ->
        path.join dest, file.name.replace pugRE, pugExt

      changes = @stream dir, watchOptions
      changes.on 'data', (file) =>
        file.dest = getDest file

        if file.exists
          file.compile =
            if pugRE.test file.name
            then pugCompilers[lang]
            else noop.arg1
          action = build
        else
          action = clear

        action.call(this, file).catch (err) ->
          log log.red('Error while processing:'), file.path
          log log.gray err.stack
