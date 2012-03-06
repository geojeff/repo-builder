**NOTE: repo-builder works in hard-coded fashion for its initial task, as a one-off variant of the code here, but the software
in the repo now won't work until nconf configuration is added a few adjustments are made.**


*repo-builder* was written to parse shell commands, git commands, and code blocks from a SproutCore sproutguides file (.textile).

Installation
============

repo-builder requires CoffeeScript plus four node modules, nconf, mkdirp, prompt, and colors.

You can install CoffeeScript globally with the -g flag if you want, or locally with:

  npm install coffee-script

And for the node.js modules:

  npm install nconf
  npm install mkdirp
  npm install prompt
  npm install colors

Locally installed npm modules go in a node_modules directory. If you installed CoffeeScript locally, the command to run it
would be:

  ./node_modules/coffee-script/bin/coffee

but if globally installed, of course, just use the coffee command.

To use repo-builder, clone the code from this repo:

  git clone git.com/geojeff/repo-builder.git

Run repo-builder with:

  coffee repo_builder.coffee

You will see prompts for:

* source document (with path)

* config path (to repo-builder.conf)

Description
===========

repo-builder will be generalized to allow parsing rules that are more flexible, but here is how it works in the first version:

* git commands are found by searching for 'GIT' on a line. In the SproutCore usage, these lines begin with 'NOTE: GIT:',
so those first characters are trimmed, leaving git commands like: git add README.md.

* Shell commands are found by searching in blocks marked by <shell> beginning lines and </shell> ending lines, for any
lines that start with $, which is trimmed, leaving shell commands like: cd /somepath/somedir.

* Code is found by searching for blocks marked by <filetype filename="/somepath/somedir/somefile.ext"> beginning lines
and </filetype> ending lines, where filetype is one of [javascript, css, html], as it works in the sproutguides system.

repo-builder translates some commands to internal treatments, such as the relation of a shell command begining with 'cd'
to 'process.chdir', the actual call made to perform a change directory. Individual operations handled include:

* change directory ('cd' becomes 'process.chdir')

* rename file ('mv' becomes 'fs.rename')

* edit file (code blocks become fs.writeFileSync calls to write the lines)

* git command (executed directly with childproc.exec)

Here is an example of an operation, as an instance of the Op class:

```
op = new Op
  func: 'process.chdir'
  arg: 'parsed-from-source-file'
  pauseBeforeNextOp: 3000
```

In the first version of repo-builder, callbacks are not used. Instead, pauses are hard-coded between ops.

repo-builder reads the lines in the source file (.textile for sproutguides), then keys on the git lines to divide the
operations into operation sets. Operation sets are added to a linked list to allow higher-level control during the
repo-building process, although this is effectively not needed in the first version.

Once the operations are added to the linked list, they are run one after another, pausing in-between, and when done,
there is a new repo ready to be pushed to github.

Ideas
=====

- Have the config file also contain op type definitions. For example, the sproutcore command would be configured
with a path to a specific bin directory, 'cd' could be mapped to 'process.chdir', etc.
