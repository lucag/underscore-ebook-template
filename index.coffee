#global module:false

"use strict"

path    = require 'path'
process = require 'child_process'
yaml    = require 'js-yaml'
fs      = require 'fs'

module.exports = (grunt, options = {}) ->
  minify  = grunt.option('minify') ? false

  libDir  = options.lib  ? "node_modules/underscore-ebook-template/lib"
  srcDir  = options.src  ? "src"
  distDir = options.dist ? "dist"

  grunt.loadNpmTasks "grunt-browserify"
  grunt.loadNpmTasks "grunt-contrib-clean"
  grunt.loadNpmTasks "grunt-contrib-connect"
  grunt.loadNpmTasks "grunt-contrib-less"
  grunt.loadNpmTasks "grunt-contrib-watch"
  # grunt.loadNpmTasks "grunt-exec"
  grunt.loadNpmTasks "grunt-css-url-embed"

  joinLines = (lines) ->
    lines.split(/[ \r\n]+/).join(" ")

  createObject = (pairs...) ->
    ans = {}
    for [ key, value ] in pairs
      ans[key] = value
    ans

  runCommand = (command, done, options = {}) ->
    grunt.log.write("Running shell command: #{command}\n")

    proc = process.exec(command, options)

    proc.stdout.on 'data', (d) -> grunt.log.write(d)
    proc.stderr.on 'data', (d) -> grunt.log.error(d)

    proc.on 'error', (err) ->
      grunt.log.error("Shell command failed with: #{err}")
      done(false)

    proc.on 'exit', (code) ->
      if code == 0
        grunt.log.write("Shell command exited with code 0")
        done()
      else
        grunt.log.error("Shell command exited with code #{code}")
        done(false)

    return

  meta = yaml.safeLoad(fs.readFileSync("./#{srcDir}/meta/metadata.yaml", 'utf8'))

  unless typeof meta.filenameStem == "string"
    grunt.fail.fatal("'filename' in metadata must be a string")

  unless !meta.exercisesRepo || typeof meta.exercisesRepo == "string"
    grunt.fail.fatal("'exercisesRepo' in metadata must be a string or null")

  unless Array.isArray(meta.pages)
    grunt.fail.fatal("'pages' in metadata must be an array of strings")

  grunt.initConfig
    clean:
      main:
        src: "dist"

    less:
      main:
        options:
          paths: [
            "node_modules"
            "#{libDir}/css"
            "#{srcDir}/css"
          ]
          compress: minify
          yuicompress: minify
          modifyVars:
            "lib-dir": "\"#{libDir}\""
        files: createObject(
          [ "#{distDir}/temp/main.noembed.css", "#{libDir}/css/main.less" ]
        )

    cssUrlEmbed:
      main:
        options:
          baseDir: "."
        files: createObject(
          [ "#{distDir}/temp/main.css", "#{distDir}/temp/main.noembed.css" ]
        )

    browserify:
      main:
        src:  "#{libDir}/js/main.coffee"
        dest: "#{distDir}/temp/main.js"
        cwd:  "."
        options:
          watch: false
          transform: if minify
            [ 'coffeeify', [ 'uglifyify', { global: true } ] ]
          else
            [ 'coffeeify' ]
          browserifyOptions:
            debug: false
            extensions: [ '.coffee' ]

    watchImpl:
      options:
        livereload: true
      css:
        files: [
          "#{libDir}/css/**/*"
          "#{srcDir}/css/**/*"
        ]
        tasks: [
          "less"
          "cssUrlEmbed"
          "pandoc:html"
        ]
      js:
        files: [
          "#{libDir}/js/**/*"
          "#{srcDir}/js/**/*"
        ]
        tasks: [
          "browserify"
          "pandoc:html"
        ]
      templates:
        files: [
          "#{libDir}/templates/**/*"
          "#{srcDir}/templates/**/*"
        ]
        tasks: [
          "pandoc:html"
          # "pandoc:pdf"
          # "pandoc:epub"
        ]
      pages:
        files: [
          "#{srcDir}/pages/**/*"
        ]
        tasks: [
          "pandoc:html"
          # "pandoc:pdf"
          # "pandoc:epub"
        ]
      metadata:
        files: [
          "#{srcDir}/meta/**/*"
        ]
        tasks: [
          "pandoc:html"
          # "pandoc:pdf"
          # "pandoc:epub"
        ]

    connect:
      server:
        options:
          port: 4000
          base: 'dist'

  grunt.renameTask "watch", "watchImpl"

  grunt.registerTask "pandoc", "Run pandoc", (target) ->
    target ?= "html"

    switch target
      when "pdf"
        output    = "--output=#{distDir}/#{meta.filenameStem}.pdf"
        template  = "--template=#{libDir}/templates/template.tex"
        variables = joinLines """
                      --variable=lib-dir:#{libDir}
                    """
        filters   = joinLines """
                      --filter=#{libDir}/filters/pdf/callout.coffee
                      --filter=#{libDir}/filters/pdf/columns.coffee
                      --filter=#{libDir}/filters/pdf/solutions.coffee
                      --filter=#{libDir}/filters/pdf/vector-images.coffee
                    """
        extras    = joinLines """
                      --include-before-body=#{libDir}/templates/cover-notes.tex
                    """
        metadata  = "#{srcDir}/meta/pdf.yaml"

      when "html"
        output    = "--output=#{distDir}/#{meta.filenameStem}.html"
        template  = "--template=#{libDir}/templates/template.html"
        variables = joinLines """
                      --variable=lib-dir:#{libDir}
                    """
        filters   = joinLines """
                      --filter=#{libDir}/filters/html/tables.coffee
                      --filter=#{libDir}/filters/html/solutions.coffee
                      --filter=#{libDir}/filters/html/vector-images.coffee
                    """
        extras    = joinLines """
                      --toc-depth=2
                      --include-before-body=#{libDir}/templates/cover-notes.html
                    """
        metadata  = "#{srcDir}/meta/html.yaml"

      when "epub"
        output    = "--output=#{distDir}/#{meta.filenameStem}.epub"
        template  = "--template=#{libDir}/templates/template.epub.html"
        variables = joinLines """
                      --variable=lib-dir:#{libDir}
                    """
        filters   = joinLines """
                      --filter=#{libDir}/filters/epub/solutions.coffee
                      --filter=#{libDir}/filters/epub/vector-images.coffee
                    """
        extras    = joinLines """
                      --epub-stylesheet=#{distDir}/temp/main.css
                      --epub-cover-image=#{srcDir}/covers/epub-cover.png
                      --include-before-body=#{libDir}/templates/cover-notes.html
                    """
        metadata  = "#{srcDir}/meta/epub.yaml"

      when "json"
        output    = "--output=#{distDir}/#{meta.filenameStem}.json"
        template  = ""
        variables = joinLines """
                      --variable=lib-dir:#{libDir}
                    """
        filters   = joinLines """
                      --filter=#{libDir}/filters/pdf/callout.coffee
                      --filter=#{libDir}/filters/pdf/columns.coffee
                      --filter=#{libDir}/filters/pdf/solutions.coffee
                    """
        extras    = ""
        metadata  = ""

      else
        grunt.log.error("Bad pandoc format: #{target}")

    command = joinLines """
      pandoc
      --smart
      #{output}
      #{template}
      --from=markdown+grid_tables+multiline_tables+fenced_code_blocks+fenced_code_attributes+yaml_metadata_block+implicit_figures+header_attributes+definition_lists
      --latex-engine=xelatex
      #{variables}
      #{filters}
      --chapters
      --number-sections
      --table-of-contents
      --highlight-style tango
      --standalone
      --self-contained
      #{extras}
      #{srcDir}/meta/metadata.yaml
      #{metadata}
      #{meta.pages.join(" ")}
    """

    runCommand(command, this.async())

  grunt.registerTask "exercises", "Download and build exercises", (target) ->
    unless meta.exercisesRepo
      return

    command = joinLines """
      rm -rf #{meta.filenameStem}-code &&
      git clone #{meta.exercisesRepo} &&
      zip -r #{meta.filenameStem}-code.zip #{meta.filenameStem}-code
    """

    runCommand(command, this.async(), { cwd: 'dist' })

  grunt.registerTask "json", [
    "pandoc:json"
  ]

  grunt.registerTask "html", [
    "less"
    "cssUrlEmbed"
    "browserify"
    "pandoc:html"
  ]

  grunt.registerTask "pdf", [
    "pandoc:pdf"
  ]

  grunt.registerTask "epub", [
    "less"
    "cssUrlEmbed"
    "pandoc:epub"
  ]

  grunt.registerTask "all", [
    "less"
    "cssUrlEmbed"
    "browserify"
    "pandoc:html"
    "pandoc:pdf"
    "pandoc:epub"
  ]

  grunt.registerTask "watch", [
    "html"
    "connect:server"
    "watchImpl"
  ]

  grunt.registerTask "default", [
    "all"
    "exercises"
  ]