'use strict'

path = require 'path'
express = require 'express'
debug = require('debug') 'jumbo:router'

Diff = require './diff'
Sync = require './sync'

diffs = {}
syncs = {}

module.exports = (options) ->
	prefix = options.web?.prefix ? ''
	views = if options.web?.views then "#{options.web.views}/" else ''
	router = express.Router()

	router.use '/api/*', require('body-parser').json()
	
	router.all '*', (req, res, next) ->
		res.locals.jumbo =
			prefix: prefix

		next()
	
	router.get '/', (req, res, next) ->
		res.render "#{views}index"
	
	router.get '/create/diff', (req, res, next) ->
		diff = new Diff options
		diffs[diff.id] = diff
		diff.init (err) ->
			if err then return next err
			
			res.redirect "#{prefix}/diff/#{diff.id}"
	
	router.get '/create/sync', (req, res, next) ->
		sync = new Sync options
		syncs[sync.id] = sync
		sync.init (err) ->
			if err then return next err
			
			res.redirect "#{prefix}/sync/#{sync.id}"
	
	router.param 'diff', (req, res, next, id) ->
		if not diffs[id]
			return next new Error "Diff not found."
		
		req.diff = diffs[id]
		next()
	
	router.param 'sync', (req, res, next, id) ->
		if not syncs[id]
			return next new Error "Sync not found."
		
		req.sync = syncs[id]
		next()
	
	router.get '/diff/:diff', (req, res, next) ->
		res.render "#{views}diff",
			jumbo:
				prefix: prefix
				diff: req.diff
	
	router.get '/sync/:sync', (req, res, next) ->
		res.render "#{views}sync",
			jumbo:
				prefix: prefix
				sync: req.sync
	
	router.post '/api/resolve/diff/:diff/:id(\\d+)', (req, res, next) ->
		req.diff.resolve req.params.id, req.body, (err, body) ->
			if err then return res.json status: 'error', message: err.message
			
			res.json body ? status: 'ok'
	
	router.post '/api/resolve/sync/:sync/:id(\\d+)', (req, res, next) ->
		req.sync.resolve req.params.id, req.body, (err, body) ->
			if err then return res.json status: 'error', message: err.message
			
			res.json body ? status: 'ok'

	router