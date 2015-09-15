'use strict'

express = require 'express'
debug = require('debug') 'jumbo:app'

process.env.NODE_ENV ?= 'development'

try
	config = require "#{process.cwd()}/.jumbo.json"
	
	config.web ?= {}
	config.web.port ?= 3000
	
	debug "config loaded"

catch ex
	console.error "Failed to load config. #{ex.message}"
	process.exit 1

app = express()
app.set 'views', "#{__dirname}/../views"
app.set 'view engine', 'jade'
app.disable 'etag'
app.use express.static("#{__dirname}/../static")
app.use require('body-parser').urlencoded(extended: false)
app.use require('./router') config

app.use (err, req, res, next) ->
	if process.env.NODE_ENV is 'development'
		console.error err.stack
	
	if res.headersSent
		return next err
	
	res.status 500
	res.render '500', error: err

app.use (req, res) ->
	res.status 404
	res.render '404'

@web = app.listen config.web.port, =>
	console.log "Jumbo webserver is listening on http://localhost:#{config.web.port}"