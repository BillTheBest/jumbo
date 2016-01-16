'use strict'

async = require 'async'
debug = require('debug') 'jumbo:sync'

###
@param {Array} a
@param {Array} b
@returns {Boolean} Return true if both arrays of columns are equal.
###

compareColumns = (a, b) ->
	columns = {}
	
	for col in a
		columns[col.name] =
			a:
				type: col.type
				primary: col.primary
	
	for col in b
		columns[col.name] ?= {}
		columns[col.name].b =
			type: col.type
			primary: col.primary
	
	for name, ab of columns
		if not ab.a? or not ab.b?
			return false
		
		if ab.a.type isnt ab.b.type
			return false
		
		if ab.a.primary isnt ab.b.primary
			return false
	
	true

class Sync
	id: null
	options: null
	tables: null
	actions: null
	resolver: null
	
	constructor: (@options) ->
		@id = Math.floor Math.random() * 9999999
		
		@tables = []
		for table, opts of @options.sync
			@tables.push new Table @, table, opts

		@actions = {}
		Object.defineProperties @actions,
			add:
				value: (action) ->
					action.id = Math.floor Math.random() * 99999999
					@[action.id] = action
					action.id
		
			get:
				value: (id) ->
					@[id]
		
			has:
				value: (id) ->
					@[id]?
			
			remove:
				value: (id) ->
					delete @[id]
	
	init: (done) ->
		debug "initializing sync"
		
		async.eachSeries ['a', 'b'], (server, next) =>
			try
				driver = require "./drivers/#{@options[server].driver}"
			catch ex
				throw new Error "Failed to load driver '#{@options[server].driver}'. #{ex.message}"
			
			debug "connecting to server '#{@options[server].name}'"
			
			@[server] = new driver @options[server]
			@[server].connect next
		
		, (err) =>
			if err then return done err
			
			debug "creating comparisons"
			
			async.each @tables, (table, next) =>
				table.compare (err) =>
					if err then return next err
				
					@actions.add table.action
					next()
			
			, done
	
	resolve: (id, data, done) ->
		if not @actions.has id
			return setImmediate -> done new Error "Action not found."
		
		action = @actions.get id
		
		if not action.do?
			return setImmediate -> done new Error "Action has nothing to do."
		
		sql = action.do
		if data.parameters
			sql = formatString sql, data.parameters

		@b.query sql, (err) =>
			if err then return done err
			
			action.do = undefined
			@actions.remove id
			
			done()

class Table
	sync: null
	name: ''
	action: null
	
	constructor: (@sync, @name, @options) ->
	
	compare: (done) ->
		async.map ['a', 'b'], (server, next) =>
			@sync[server].download @name, @options, next
		
		, (err, recordsets) =>
			if err then return done err
			
			txt = []
			[a, b] = recordsets
			
			debug "table '#{@name}' - #{a.length} rows on '#{@sync.options.a.name}', #{b.length} rows on '#{@sync.options.b.name}'"
			
			if a.length is 0 and b.length is 0
				return done null

			if a.primary and b.primary
				# both has primary keys so we can compare changes
				
				debug "table '#{@name}' - primary key is present on both tables"
				
				if Array.isArray(@options.ignore) and @options.ignore.length
					# remove ignored columns
					a.records.forEach (item) => item.columns.ignore @options.ignore
					b.records.forEach (item) => item.columns.ignore @options.ignore

				if a.length and b.length
					# compare columns to make sure both tables are the same
					if not compareColumns a.records[0].columns, b.records[0].columns
						@action =
							name: @name
							error: "Schema of table '#{@name}' doesn't match on both servers."
							
						return done null
					
					# compare
					sql = a.toUpdate b
					txt.push sql if sql
				
				else if a.length
					# insert only
					txt.push a.toInsert()
				
				else if b.length
					# delete only
					txt.push b.toDelete()
			
			else
				# witout primary key we cant compare so we must truncate table and insert all manually
				txt.push "-- table '#{@name}' has no primary key"
				txt.push "truncate table #{@name};"
				
				sql = a.toInsert()
				txt.push sql if sql
			
			@action =
				name: @name
				do: if txt.length then txt.join('\n') else null
			
			done null

module.exports = Sync
