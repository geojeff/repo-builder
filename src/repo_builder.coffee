# -----
#

util         = require "util"
fs           = require "fs"
path_module  = require "path"
childproc    = require "child_process"
mkdirp       = require "mkdirp"
#nconf        = require "nconf"
prompt       = require "prompt"
colors       = require "colors"

lineIsGitNoteStart = (line) ->
  if line.indexOf('GIT') isnt -1 and line[0...4] is 'NOTE'
    return true
  false

lineIsShellBlockStart = (line) ->
  if line.indexOf('<shell') isnt -1
    return true
  false

lineIsShellBlockEnd = (line) ->
  if line.indexOf('</shell') isnt -1
    return true
  false

lineIsFileBlockStart = (line) ->
  if line.indexOf('<javascript') isnt -1
    return true
  if line.indexOf('<css') isnt -1
    return true
  if line.indexOf('<html') isnt -1
    return true
  false
  
lineIsFileBlockEnd = (line) ->
  if line.indexOf('</javascript') isnt -1
    return true
  if line.indexOf('</css') isnt -1
    return true
  if line.indexOf('</html') isnt -1
    return true
  false

parseRepoFromDocument = (lines) ->
  currentPath = ''
  currentFileBlockType = ''
  fileEdits = {}
  currentFileBlock = {}
  currentVersion = 0
  readingFileBlock = false
  fileBlockIndex = 0

  readingShellBlock = false

  shellCommands = {}
  gitCommands = {}

  for line,i in lines
    line = line.replace('~/development/sproutcore/', "#{rootDirectory}/")
    if lineIsFileBlockStart(line)
      parts = line.split(' ')
      fileType = parts[0]
      fileType = fileType[1..fileType.length-1]
      currentFileBlockType = fileType
      path = line[line.indexOf('filename="')+10..line.length-3]
      console.log 'lineIsFileBlockStart, path: ', path
      version = 0
      if path of fileEdits
        version = (v for v of fileEdits[path]['versions']).length
      currentFileBlock = {}
      currentFileBlock['path'] = path
      currentPath = currentFileBlock['path']
      currentVersion = version
      #currentFileBlock = {}
      currentFileBlock['lines'] = []
      readingFileBlock = true
    else if lineIsFileBlockEnd(line) and readingFileBlock
      console.log 'lineIsFileBlockEnd'
      line = line.trim()
      if line[2..currentFileBlockType.length+1] is currentFileBlockType
        currentFileBlock['file block index'] = fileBlockIndex
        currentFileBlock['starting line index'] = i - currentFileBlock['lines'].length
        currentFileBlock['ending line index'] = i
        currentFileBlock['type'] = currentFileBlockType
        currentFileBlock['version'] = currentVersion
        unless currentPath of fileEdits
          fileEdits[currentPath] = {}
          fileEdits[currentPath]['versions'] = {}
        console.log "currentPath: #{currentPath}"
        console.log "  v: #{currentVersion}"
        fileEdits[currentPath]['versions'][currentVersion] = currentFileBlock
        readingFileBlock = false
    else if readingFileBlock
      console.log 'readingFileBlock'
      currentFileBlock['lines'].push line
    else if lineIsShellBlockStart(line)
      console.log 'lineIsShellBlockStart'
      readingShellBlock = true
    else if lineIsShellBlockEnd(line)
      console.log 'lineIsShellBlockEnd'
      readingShellBlock = false
    else if readingShellBlock
      console.log 'readingShellBlock'
      if line[0] is '$'
        shellCommands[i] = line[2..line.length]
    else if lineIsGitNoteStart(line)
      console.log 'lineIsGitNoteStart'
      gitCommands[i] = line[line.indexOf('git')..line.length].trim()
  
  [ fileEdits, shellCommands, gitCommands ]

class Op
  constructor: (options) ->
    @func = 'childproc.exec' # Also: 'process.chdir', 'fs.writeFile'
    @arg = ''
    @path = ''
    @fileEdit = null
    @pauseBeforeNextOp = 2000
    @next = null

    @[key] = options[key] for own key of options

    @exec = =>
      switch @func
        when 'childproc.exec'
          childproc.exec @arg
          if @arg[0...3] is 'git'
            console.log('GIT op performed:', @arg)
          else
            console.log('sproutcore op performed:', @arg)
        when 'process.chdir'
          console.log 'chdir', @arg
          process.chdir @arg
          console.log('changed directory to:', @arg) if @arg isnt ''
        when 'sproutcore'
          currentWorkingDirectory = process.cwd()
          console.log 'this is cwd', currentWorkingDirectory
          #childproc.exec "#{absoluteSproutCoreBinDirectory}/sproutcore @arg"
          # the line above doesn't work nor does the one below, for some reason <-- special-cased TodosThree app creation for 1.8 release
          #
          #  NOTE: The problem could have been the pause time -- had to bump it up to 6
          #        in a couple of ops.
          #
          childproc.exec "../#{relativeSproutCoreBinDirectory}/sproutcore @arg"
          console.log('sproutcore op performed:', @arg) if @arg isnt ''
        when 'mkdir'
          try
            mkdirp.sync(@path)
          catch e
            throw e  if e.code isnt "EEXIST"
          console.log('made directory:', @path)
        when 'fs.writeFile'
          currentWorkingDirectory = process.cwd()
          process.chdir "#{rootDirectory}/getting_started"
          try
            mkdirp.sync(path_module.dirname(@path))
          catch e
            throw e  if e.code isnt "EEXIST"
          fs.writeFileSync @path, @fileEdit['lines'].join('\n')
          console.log 'changing back to', currentWorkingDirectory
          process.chdir currentWorkingDirectory
          console.log('edited file:', @path)
        when 'fs.rename'
          childproc.exec "mv #{@arg}"
          filenames = @arg.split(' ')
          fs.renameSync(filenames[0], filenames[1])
          console.log('renamed file:', filenames[0], 'to', filenames[1])

      setTimeout @next.exec, @pauseBeforeNextOp if @next?

forEach = (array, action) ->
  for element in array
    action element

sum = (numbers) ->
  total = 0
  forEach numbers, (number) -> total += number
  total

class OpSet
  constructor: (@name='', @ops=[]) ->
    @pauseBeforeNextOpSet = (sum (op.pauseBeforeNextOp for op in ops)) + 2000
    @next = null

  # *exec* fires on the head op.
  #
  exec: =>
    @ops[0].exec()
    setTimeout @next.exec, @pauseBeforeNextOpSet if @next?

class RepoBuilder
  constructor: ->
    @opSets = []

  addOpSet: (name, ops) ->
    opSet = new OpSet name, ops

    # Set op.next for all but the last op, which will have the default next = null.
    op.next = opSet.ops[i+1]  for op,i in opSet.ops[0...opSet.ops.length-1]
    
    @opSets.push opSet

  # *exec* fires on the head opSet.
  #
  exec: ->
    # Set opSet.next for all but the last opSet, which will have the default next = null.
    opSet.next = @opSets[i+1]  for opSet,i in @opSets[0...@opSets.length-1]

    console.log 'RepoBuilder.exec()'
    @opSets[0].exec()

pathAndFileVersionAtLineIndex = (lineIndex, fileEdits) ->
  for path of fileEdits
    for version of fileEdits[path]['versions']
      start = fileEdits[path]['versions'][version]['starting line index']
      end = fileEdits[path]['versions'][version]['ending line index']
      if start < lineIndex < end
        return [path, version]
  [ null, null ]

rootDirectory = process.cwd()
sourceDocument = ''

prompt.message = "Question!".blue
prompt.delimiter = ">|".green

prompt.start()
  
prompts = []

prompts.push
  name: "sourceDocument"
  message: "Path and filename of source document)".magenta
prompts.push
  name: "configPath"
  message: "Path to your repo-builder.conf file)".magenta

prompt.get prompts, (err, result) ->
  if result.sourceDocument?
    console.log "You said your source document is: ".cyan + result.sourceDocument.cyan
    sourceDocument = result.sourceDocument
  if result.configPath?
    console.log "You said your configPath is: ".cyan + result.configPath.cyan
    configPath = result.configPath

  addOpSetsForDocument = (fileEdits, shellCommands, gitCommands) ->
    sortedGitLineIndices = (index for index of gitCommands).sort()
    ops = []
    maxAlreadyHandledIndex = 0
    setCount = 0
    lineIndex = 0
    for gitLineIndex in sortedGitLineIndices
      while lineIndex < gitLineIndex
      #for lineIndex in [maxAlreadyHandledIndex..gitLineIndex]
        [path,version] = pathAndFileVersionAtLineIndex(lineIndex, fileEdits)
        if path and version
          ops.push new Op
            func: 'fs.writeFile'
            path: path
            fileEdit: fileEdits[path]['versions'][version]
            pauseBeforeNextOp: 2000
          #maxAlreadyHandledIndex = fileEdits[path]['versions'][version]['ending line index']
          lineIndex = fileEdits[path]['versions'][version]['ending line index']
        else if lineIndex of shellCommands
          shellCommand = shellCommands[lineIndex]
          if shellCommand[0...2] is 'cd'
            ops.push new Op
              func: 'process.chdir'
              arg: shellCommand[3..shellCommand.length-1]
              pauseBeforeNextOp: 2000
          else if shellCommand[0...5] is 'mkdir'
            ops.push new Op
              func: 'mkdir'
              path: shellCommand[6..shellCommand.length-1]
              pauseBeforeNextOp: 2000
          else if shellCommand[0...2] is 'mv'
            ops.push new Op
              func: 'fs.rename'
              arg: shellCommand[3..shellCommand.length-1]
              pauseBeforeNextOp: 2000
          else if shellCommand[0...10] is 'sproutcore'
            ops.push new Op
              func: 'sproutcore'
              arg: shellCommand[11..shellCommand.length-1]
              pauseBeforeNextOp: 6000
          else
            ops.push new Op
              func: 'childproc.exec'
              arg: shellCommands[lineIndex]
              pauseBeforeNextOp: 2000
          lineIndex += 1
        else
          lineIndex += 1
      ops.push new Op
        func: 'childproc.exec'
        arg: gitCommands[gitLineIndex]
        pauseBeforeNextOp: 2000
      repoBuilder.addOpSet "build up TodosThree #{setCount}", ops
      ops = []
  
  repoBuilder = new RepoBuilder()

  # Use nconf to parse opSets and within those, ops, from configPath/repo-builder.conf,
  # calling repoBuilder.addOptSet(ops)
  
  lines = fs.readFileSync(sourceDocument, "utf-8").split '\n'

  [fileEdits,shellCommands,gitCommands] = parseRepoFromDocument(lines)

  addOpSetsForDocument(fileEdits, shellCommands, gitCommands)
  
  repoBuilder.exec()
