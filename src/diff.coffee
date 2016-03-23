'use strict'

async = require 'async'
debug = require('debug') 'jumbo:diff'

LABELS =
	users: 'Users'
	schemas: 'Schemas'
	tables: 'Tables'
	functions: 'Functions'
	views: 'Views'

formatString = (text, data) ->
	text.replace /{{([^}]*)}}/g, (p) ->
		key = p.substr(2, p.length - 4).split '.'
		
		if key.length > 1
			cur = data
			while cur and key.length
				cur = cur[key.shift()]
				
			value = cur ? ''
		
		else
			value = data[key[0]]
			
		value

class Diff
	id: null
	options: null
	categories: null
	actions: null
	resolver: null
	
	constructor: (@options) ->
		@id = Math.floor Math.random() * 9999999

		@categories = []
		@categories.push new Category @, 'users', @options.diff.users
		@categories.push new Category @, 'schemas', @options.diff.schemas
		@categories.push new Category @, 'tables', @options.diff.tables
		@categories.push new Category @, 'functions', @options.diff.functions
		@categories.push new Category @, 'views', @options.diff.views

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
		debug "initializing diff"
		
		async.eachSeries ['a', 'b'], (server, next) =>
			try
				driver = require "./drivers/#{@options[server].driver}"
			catch ex
				throw new Error "Failed to load driver '#{@options[server].driver}'. #{ex.message}"
			
			debug "connecting to server '#{@options[server].name}'"
			
			@[server] = new driver @options[server]
			@[server].connect (err) =>
				if err then return next err
				
				debug "fetching data from server '#{@options[server].name}'"
				
				@[server].ignoredUsers = @options.diff.users?.ignore ? []
				@[server].fetch next
		
		, (err) =>
			if err then return done err
			
			debug "creating comparison"
			
			for category in @categories
				category.compare()
				
				for action in category.actions
					@actions.add action
			
			done()
	
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
			action.b = action.a
			@actions.remove id
			
			done()

class Category
	diff: null
	name: ''
	label: ''
	
	actions: null
	ignore: null
	
	constructor: (@diff, @name, options) ->
		@label = LABELS[@name]
		@ignore = options?.ignore ? []
		@actions = []
	
	###
	@returns {Array} Array of actions
	###
	
	compare: ->
		founda = {}
		foundb = {}
		kinds = []
		
		for item in @diff.a[@name]
			founda[item.name] = item
			if @ignored item.name then continue
			kinds.push item.name

		for item in @diff.b[@name]
			foundb[item.name] = item
			if founda[item.name] then continue
			if @ignored item.name then continue
			kinds.push item.name
		
		for kind in kinds.sort()
			if founda[kind]
				if foundb[kind]
					# both has it
					@actions.push
						name: kind
						a: founda[kind]
						b: foundb[kind]
						do: founda[kind].compare foundb[kind]
				
				else
					# only a has it
					@actions.push
						name: kind
						a: founda[kind]
						b: null
						do: founda[kind].constructor.create.call @, founda[kind]
			
			else
				# only b has it
				@actions.push
					name: kind
					a: null
					b: foundb[kind]
					do: foundb[kind].constructor.drop.call @, foundb[kind]
		
		@
	
	ignored: (name) ->
		for item in @ignore
			if '*' is item.substr item.length - 1
				if item is "#{name.substr 0, item.length - 1}*"
					return true
			
			else
				if item is name
					return true
		
		false

module.exports = Diff
