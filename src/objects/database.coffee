'use strict'

{EventEmitter} = require 'events'

class Database extends EventEmitter
	__type: 'database'
	
	config: null
	schemas: null
	users: null
	functions: null
	tables: null
	views: null
	connected: false
	
	constructor: (@config) ->
		super()
		
		@schemas = []
		@users = []
		@functions = []
		@tables = []
		@views = []
	
	connect: (done) ->
		setImmediate -> done new Error "Connect method is not implemented."
	
	fetch: (done) ->
		setImmediate -> done new Error "Fetch method is not implemented."

module.exports = Database