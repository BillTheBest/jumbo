COMPARE = (a, b = []) ->
	founda = {}
	foundb = {}
	kinds = []
	txt = []
	
	for item in a
		founda[item.name] = item
		kinds.push item.name

	for item in b
		foundb[item.name] = item
		if founda[item.name] then continue
		kinds.push item.name
	
	for kind in kinds.sort()
		if founda[kind]
			if foundb[kind]
				# both has it
				sql = founda[kind].compare foundb[kind]
				txt.push sql if sql
			
			else
				# only a has it
				sql = founda[kind].constructor.create.call @, founda[kind]
				txt.push sql if sql
		
		else
			# only b has it
			sql = foundb[kind].constructor.drop.call @, foundb[kind]
			txt.unshift sql if sql # drops first
	
	if txt.length is 0
		return null # no changes
	
	txt.join '\n'

class Table
	__type: 'table'
	
	columns: null
	constraints: null
	indexes: null
	triggers: null
	
	constructor: ->
		@columns = []
		@constraints = []
		@indexes = []
		@triggers = []
		
		@columns.compare = COMPARE.bind null, @columns
		@constraints.compare = COMPARE.bind null, @constraints
		@indexes.compare = COMPARE.bind null, @indexes
		@triggers.compare = COMPARE.bind null, @triggers

module.exports = Table
