class Record
	columns: null
	
	constructor: ->
		@columns = []
		
		# to prevent enumeration of byName
		Object.defineProperty @columns, 'byName',
			value: {}
	
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