class Record
	columns: null
	
	constructor: ->
		@columns = []
		
		# to prevent enumeration of byName
		Object.defineProperty @columns, 'byName',
			value: {}
		
		# to prevent enumeration of byName
		Object.defineProperty @columns, 'ignore',
			value: (ignored) ->
				if not Array.isArray ignored
					ignored = [ignored]
				
				for name in ignored
					@byName[name] = undefined
					
					for item, index in @ when item.name is name
						@splice index, 1
						break
				
				@
	
	get: (name) ->
		@columns.byName[name]
	
	push: (column) ->
		@columns.byName[column.name] = column
		@columns.push column
	
	toInsert: ->
		throw new Error "toInsert method is not implemented."
	
	toDelete: ->
		throw new Error "toDelete method is not implemented."
	
	toUpdate: (b) ->
		throw new Error "toUpdate method is not implemented."

module.exports = Record
