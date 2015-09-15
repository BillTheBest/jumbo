'use strict'

###
@param {Array} primary
@param {Array} records
@param {Record} find
@returns {Record}
###

findAndSlice = (primary, records, find) ->
	for record, index in records
		matches = true
		for column in primary
			if record.get(column).value isnt find.get(column).value
				matches = false
				break
		
		if not matches
			continue
		
		records.splice index, 1
		return record
	
	null

class Recordset
	table: ''
	records: null
	primary: null
	
	constructor: ->
		@records = []
	
	push: (record) ->
		record.table = @table
		@records.push record

	toInsert: ->
		if @records.length is 0 then return null
		(record.toInsert() for record in @records).join '\n'
	
	toDelete: ->
		if @records.length is 0 then return null
		(record.toDelete() for record in @records).join '\n'
	
	toUpdate: (b) ->
		txt = []
		b = b.records.slice 0 # copy records
		
		for ra in @records
			rb = findAndSlice @primary, b, ra

			if not rb
				# row not found in b
				txt.push ra.toInsert()
				continue
			
			# compare values
			sql = ra.toUpdate rb
			txt.push sql if sql
		
		# delete rest of the records in b
		for rb in b
			txt.push rb.toDelete()
		
		if txt.length is 0
			return null

		txt.join '\n'

Object.defineProperty Recordset.prototype, 'length',
	get: -> @records.length

module.exports = Recordset