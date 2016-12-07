{CompositeDisposable, File} = require 'atom'
{parse, stringify} = JSON
{readFileSync, writeFileSync} = require 'fs'
{resolve, dirname, join} = require 'path'
glob = require 'glob-all'
match = require 'minimatch'
require 'require-cson'
{exec} = require 'child_process' # TODO DELETE

subs = new CompositeDisposable

module.exports =
  package: require '../package.json'
  settings: -> atom.config.get @package.name

  project: atom.project?.getPaths()[0]
  #backup: 'sync-settings.extraFiles'

  # Snippets
  global: "#{atom.configDirPath}/snippets"
  local: ['?(.)snippets{.cson,}','package.json']
  # TODO add support for module.exports.snippets? #?(.)snippets{.@(cson|js|coffee),}

  # Notifications
  #Error: -> "Snippet '#{@name}' is invalid."
  success: -> "#{@package.name}: Compiled snippets are available."
  #dismissable: true

#-------------------------------------------------------------------------------

  #subs: new CompositeDisposable
  activate: ->
    #require 'require-cson' #cson-parser
    #{@load} = require './load'
    #{@read} = require './read'

    @recursive = '**/*.[cj]son'
    files = ["#{@global}/#{@recursive}"].concat @local
    #@files.push '?(.)@(project|atom).cson' TODO from project-config API

    @glob files, (files) => exec "echo '#{files}' >> '#{@project}'/TEST"

    #@read files

    # TODO break Gist sync into sync-snippets-gists package?
    #if atom.config.get 'modular-snippets.syncSnippets'
      #

    # Backup snippets with sync-settings if installed
    #if atom.packages.isPackageLoaded 'sync-settings'
      #atom.config.pushAtKeyPath 'sync-settings.syncSnippets', false
      #unless @pattern in atom.config.get @backup
        #atom.config.pushAtKeyPath @backup, @pattern

#-------------------------------------------------------------------------------

    ### Automatically reload newly created snippets.
    subs.add atom.workspace.observeTextEditors (editor) =>
      editor.onDidSave ({path}) =>
        @globs?.some ({matches}) =>
          #console.log JSON.stringify matches, null, 2
          if matches?[0]?[path]
            console.log "match"

          unless matches?[0][path]
            @files.some (snippets) => #cwd: @project #@options
              if match path, snippets, {dot: true, matchBase: true}
                #@cache = true
                @watch path #; @read path
    ###

    subs.add atom.commands.add 'atom-workspace',
      "#{@package.name}:open", => #application:open-your-snippets
        glob @global+'{,.cson}', (err, snippets) => @open snippets

#-------------------------------------------------------------------------------

  #provide: -> # API TODO
    #load: (snippets) =>
      #@load @read snippets

  watch: (file) -> # Automatically reload modified snippets.
    file = new File file
    subs.add file.onDidChange => @read file.path #@load @read file.path
    #subs.add file.onDidRename =>
    subs.add file.onDidDelete =>
      #@unload file.path TODO
      file.dispose()

    #folder = new Folder item
    #subs.add folder.onDidChange => @glob path.join folder, @recursive

  glob: (snippets, callback) -> #read:
  # TODO new Promise (resolve) =>
    options =
      cwd: @project # FIXME for external API
      dot: true
      #matchBase: true
      realpath: true #absolute
      #nodir: true
      stat: true #mark
      #cache: TODO

    #.reduce TODO https://youtube.com/watch?v=1DMolJ2FrNY
    {globs} = glob snippets, options, =>
      globs?.map ({cache, found}) =>
        found?.map (path) =>

          if cache?[path] is 'DIR'
            path = join path, @recursive
            @glob path, callback
          else
            @watch path
            callback path

  # TODO
  load: (snippets, path) ->
    # Handle duplicate grammar scopes.
    keys(snippets).map (scope) ->
      #.reduce TODO https://youtube.com/watch?v=1DMolJ2FrNY
      @merge snippets, scope, path

  load: (snippets) ->
    {load} = require './load'
    @write stringify load snippets, @path

#-------------------------------------------------------------------------------

  # Merge snippets across multiple files into a single valid JSON {object}.
  merge: (path, scope, snippets) -> #construct: #concat:
    @snippets ?= {}
    for name, snippet of snippets[scope]
      try
        snippet = @process path, name, snippet
        @snippets[scope] = assign @snippets[scope] ? {}, snippet
        #assign @snippets, snippet
      catch err
        @error err
    #return @snippets

  # Process each snippet
  process: (file, name, snippet) -> #filter: #prep[are]:
    return unless @valid snippet, name

    # Prevent Atom from caching this.
    if file.endsWith 'package.json'
      delete require.cache[require.resolve file]

    if snippet.file? # Read in snippet.body from file:'path'.
      snippet.file = @substitute file, snippet.file

    # Ensure snippet has a unique ID to avoid overriding others.
    uid = @uid name, file
    return "#{uid}": snippet #[uid]:

  # Ensure snippet has a unique ID to avoid overriding others.
  uid: (name, path) -> #Math.random().toString(16).substr 2,4
    path = atom.project?.relativizePath path
    return name + " " + path[1].replace atom.configDirPath,"ATOM_HOME" #~

  valid: (snippet, name) -> #unless typeof snippet is 'object'
    {prefix, body, file} = parse stringify snippet
    if prefix? and (body? or file?)
      return true
    else ['prefix','body'].find (key) -> unless snippet[key]?
      throw "Snippet '#{name}' is missing #{key}."

  # Read in snippet.body from file:'path'.
  substitute: (file, path) ->
    {readFileSync} = require 'fs'
    {resolve, dirname} = require 'path'
    file = resolve dirname(path), file
    readFileSync file,'utf8'

#-------------------------------------------------------------------------------

  write: (snippets) ->
    writeFileSync "#{atom.configDirPath}/snippets.json", snippets
    # TODO Atomic
    #file = "#{atom.configDirPath}/snippets.json"
    #exec "echo '#{snippets}' > .'#{file}' && mv {.,}'#{file}'"
    if @settings().notify
      atom.notifications.addSuccess @success(), dismissable: true

  remove: (snippet) -> #path
    keys(@snippets).map (scope) =>
      delete @snippets[scope][snippet]

  # Remove snippets associated with file.
  unload: (file) -> #path
    keys(@snippets).map (scope) =>
      keys(@snippets[scope]).map (snippet) =>
        @remove snippet if snippet.endsWith file #path

  open: (snippets) -> # folder
    atom.open pathsToOpen: snippets

  #clear: -> # duplicate notifications TODO
    #atom.notifications.getNotifications().forEach (notification) ->
      #notification.dismiss()
    #atom.notifications.clear()

  error: (err) -> #{stack})
    atom.notifications.addError 'modular-snippets', #@package.name
      #icon: 'bug' #plug #alert
      detail: err #description # Markdown
      stack: err.stack ? @path #:0:0
      dismissable: true
      #buttons: [
        #text: "Edit Snippets"
        #onDidClick: => @open @path #:0:0 #newWindow: false
      #]
#-------------------------------------------------------------------------------
  deactivate: -> subs.dispose()
