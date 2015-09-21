'use strict'

async = require 'async'
pg = require 'pg'
Database = require '../objects/database'
User = require '../objects/user'
Schema = require '../objects/schema'
Function = require '../objects/function'
Table = require '../objects/table'
Column = require '../objects/column'
Constraint = require '../objects/constraint'
Index = require '../objects/index'
Trigger = require '../objects/trigger'
View = require '../objects/view'
Recordset = require '../objects/recordset'
Record = require '../objects/record'
debug = require('debug') 'jumbo:pg'

CLASS =
	f: 'function'
	r: 'table'

PRIVILEGE =
	U: 'usage'
	C: 'create'
	X: 'execute'
	r: 'select'
	w: 'update'
	a: 'insert'
	d: 'delete'
	D: 'truncate'
	x: 'references'
	t: 'trigger'
	c: 'connect'
	T: 'temporary'

###

###

class PGDatabase extends Database
	defaultPrivileges: null
	
	constructor: ->
		super arguments...
		
		@defaultPrivileges = {}
	
	###
	Connect to the database.
	
	@callback done A callback which is called after connection has established, or an error has occurred.
		@param {Error} err Error on error, otherwise null.
	###
	
	connect: (done) ->
		pg.connect @config.connectionString, (err, client, release) =>
			if err
				debug "connection to server '#{@config.name}' failed. #{err.message}"
				return done? err
			
			debug "server '#{@config.name}' connected."
			
			@connected = true
			release()
			done null
	
	###
	Query the database.
	
	@param {String} command Command to execute.
	@param {Array} [params] Command parameters.
	@callback done A callback which is called after query has completed, or an error has occurred.
		@param {Error} err Error on error, otherwise null.
		@param {Array} rows Rows returned by the query.
	###
	
	_query: (command, params, done) ->
		if 'function' is typeof params
			done = params
			params = null
		
		if not @connected
			setImmediate => done new Error "Server '#{@config.name}' is not connected."
		
		#debug "executing query '#{command}' with arguments", params
		
		pg.connect @config.connectionString, (err, client, release) ->
			if err then return done err
			
			client.query command, params, (err, result) ->
				release()
				if err then return done err
				
				#debug "query done with result", result
			
				done null, result.rows, result.fields
	
	download: (table, done) ->
		# find out primary keys
		@_query "select a.attname, format_type(a.atttypid, a.atttypmod) as atttype, (select true from pg_index i where a.attrelid = i.indrelid and a.attnum = any(i.indkey) and i.indisprimary) as attprim from pg_catalog.pg_attribute a where a.attrelid = $1::regclass and a.attnum > 0 and not a.attisdropped order by a.attnum asc", [table], (err, columns) =>
			if err then return done err
			
			pkey = (col.attname for col in columns when col.attprim)
			if pkey.length is 0 then pkey = null

			@_query "select * from #{table};", (err, rows) ->
				if err then return done err
				
				recordset = new Recordset
				recordset.table = table
				recordset.primary = pkey
				for row in rows
					record = new PGRecord
					
					for col in columns
						record.push
							name: col.attname
							type: col.atttype
							primary: col.attprim
							value: row[col.attname]
					
					recordset.push record
				
				done null, recordset
	
	fetch: (done) ->
		async.series [
			(next) =>
				@_query "select oid from pg_catalog.pg_roles where rolname = session_user", (err, rows) =>
					if err then return done err

					@loginID = rows[0].oid
					
					next()
					
			(next) =>
				@_query "select defaclobjtype, defaclacl from pg_default_acl where defaclnamespace = 0 and defaclrole = $1::oid", [@loginID], (err, rows) =>
					if err then return done err

					for row in rows
						@defaultPrivileges[CLASS[row.defaclobjtype]] = PGPrivilege.fromACL row.defaclacl
					
					next()

			(next) =>
				@_query "select rolname, oid, rolinherit, rolcanlogin from pg_catalog.pg_roles order by rolname asc", (err, rows) =>
					if err then return done err

					for row in rows
						user = new PGUser
						user.id = row.oid
						user.name = row.rolname
						user.inherit = row.inherit
						user.canlogin = row.canlogin
						
						@users.push user
					
					next()

			(next) =>
				@_query "select n.oid, n.nspname, r.rolname, n.nspacl, (select json_agg(json_build_object('type', d.defaclobjtype, 'acl', d.defaclacl::text)) from pg_default_acl d where d.defaclnamespace = n.oid and d.defaclrole = $1::oid) as nspdefacl from pg_catalog.pg_namespace n inner join pg_catalog.pg_roles r on r.oid = n.nspowner where n.nspname != 'information_schema' and n.nspname not like 'pg_%'", [@loginID], (err, rows) =>
					if err then return done err

					for row in rows
						schema = new PGSchema
						schema.id = row.oid
						schema.name = row.nspname
						schema.owner = row.rolname
						schema.privileges = PGPrivilege.fromACL row.nspacl, schema
						
						for acl in row.nspdefacl ? []
							schema.defaultPrivileges[CLASS[acl.type]] = PGPrivilege.fromACL acl.defaclacl
						
						@schemas.push schema
					
					next()

			(next) =>
				@_query "select c.oid, n.nspname || '.' || c.relname as relname, r.rolname, c.relacl,
					(select json_agg(json_build_object('name', a.attname, 'type', format_type(a.atttypid, a.atttypmod), 'notnull', a.attnotnull, 'default', d.adsrc, 'sequence', (select true
						from pg_depend dd
						inner join pg_class ss on ss.oid = dd.objid
						inner join pg_attribute aa on (aa.attrelid, aa.attnum) = (dd.refobjid, dd.refobjsubid)
						where ss.relkind = 'S' and dd.refobjid = c.oid and aa.attname = a.attname)) order by a.attnum)
					from pg_catalog.pg_attribute a
					left join pg_catalog.pg_attrdef d on (a.attrelid, a.attnum) = (d.adrelid, d.adnum)
					where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped) as relcols,
					
					(select json_agg(json_build_object('name', o.conname, 'def', pg_get_constraintdef(o.oid, true)))
					from pg_constraint o
					where o.conrelid = c.oid) as relcon,
					
					(select json_agg(json_build_object('name', cc.relname, 'def', pg_get_indexdef(ii.indexrelid, 0, true)))
					from pg_index ii
					inner join pg_class cc on cc.oid = ii.indexrelid
					where ii.indrelid = c.oid and not ii.indisprimary and not ii.indisunique) as relind,
					
					(select json_agg(json_build_object('name', t.tgname, 'def', pg_get_triggerdef(t.oid, true)))
					from pg_trigger t
					where t.tgrelid = c.oid and not t.tgisinternal) as reltg
				
				from pg_class c
				inner join pg_catalog.pg_namespace n on c.relnamespace = n.oid
				inner join pg_catalog.pg_roles r on r.oid = c.relowner
				inner join pg_catalog.pg_attribute a on a.attrelid = c.oid
				where c.relkind = 'r' and n.nspname != 'information_schema' and n.nspname not like 'pg_%'
				group by c.oid, n.nspname, c.relname, r.rolname, c.relacl
				order by n.nspname asc, c.relname asc", (err, rows) =>
					if err then return done err

					for row in rows
						table = new PGTable
						table.id = row.oid
						table.name = row.relname
						table.owner = row.rolname
						table.privileges = PGPrivilege.fromACL row.relacl, table
						
						for col in row.relcols ? []
							column = new PGColumn
							column.table = table
							column.name = col.name
							column.type = col.type
							column.notnull = col.notnull
							column.default = col.default
							
							if col.sequence
								column.type = if col.type is 'bigint' then 'bigserial' else 'serial'
								column.default = null
							
							column.definition = "#{column.name} #{column.type}#{if column.notnull then " not null" else ""}#{if column.default then " default #{column.default}" else ""}"
							
							table.columns.push column
						
						for con in row.relcon ? []
							constraint = new PGConstraint
							constraint.table = table
							constraint.name = con.name
							constraint.definition = con.def
							
							table.constraints.push constraint
						
						for ind in row.relind ? []
							index = new PGIndex
							index.table = table
							index.name = ind.name
							index.definition = ind.def
							
							table.indexes.push index
						
						for tg in row.reltg ? []
							trigger = new PGTrigger
							trigger.table = table
							trigger.name = tg.name
							trigger.definition = tg.def
							
							table.triggers.push trigger
						
						@tables.push table
					
					next()

			(next) =>
				@_query "select f.oid, n.nspname || '.' || f.proname || '(' || pg_get_function_identity_arguments(f.oid) || ')' as proname, r.rolname, f.proacl, pg_get_functiondef(f.oid) as prosrc from pg_catalog.pg_proc f inner join pg_catalog.pg_roles r on r.oid = f.proowner inner join pg_catalog.pg_namespace n on n.oid = f.pronamespace where n.nspname != 'information_schema' and n.nspname not like 'pg_%' and not f.proisagg order by n.nspname asc, f.proname asc", (err, rows) =>
					if err then return done err

					for row in rows
						func = new PGFunction
						func.id = row.oid
						func.name = PGFunction.normalizeName row.proname
						func.owner = row.rolname
						func.definition = row.prosrc
						func.privileges = PGPrivilege.fromACL row.proacl, func
						
						@functions.push func
					
					next()

			(next) =>
				@_query "select c.oid, n.nspname || '.' || c.relname as relname, r.rolname, c.relacl, pg_get_viewdef(c.oid, true) as relsrc from pg_class c inner join pg_catalog.pg_namespace n on c.relnamespace = n.oid inner join pg_catalog.pg_roles r on r.oid = c.relowner where c.relkind = 'v' and n.nspname != 'information_schema' and n.nspname not like 'pg_%'", (err, rows) =>
					if err then return done err

					for row in rows
						view = new PGView
						view.id = row.oid
						view.name = row.relname
						view.owner = row.rolname
						view.definition = row.relsrc
						view.privileges = PGPrivilege.fromACL row.relacl, view
						
						@views.push view
					
					next()
		
		], done
	
	query: (command, done) ->
		debug "query '#{command}' on server '#{@config.name}'"
		@_query command, done

class PGUser extends User
	@create: (a) ->
		"create role #{a.name}#{if a.canlogin then " login" else " nologin"} encrypted password '{{password}}' nosuperuser#{if a.inherit then " inherit" else " noinherit"} nocreatedb nocreaterole noreplication;"
	
	@drop: (b) ->
		"drop role #{b.name};"
		
	compare: (b) ->
		txt = []

		if @canlogin isnt b.canlogin
			if @canlogin
				txt.push " login"
			else
				txt.push " nologin"
				
		if @inherit isnt b.inherit
			if @inherit
				txt.push " inherint"
			else
				txt.push " noinherit"
		
		if txt.length is 0
			return null # no changes
		
		"alter role #{a.name}#{txt.join ''};"

class PGSchema extends Schema
	defaultPrivileges: null
	
	@create: (a) ->
		"create schema #{a.name}\n  authorization #{a.owner};"
	
	@drop: (b) ->
		"drop schema #{b.name};"
	
	constructor: ->
		super arguments...
		
		@defaultPrivileges = {}
		
	compare: (b) ->
		txt = []

		if @owner isnt b.owner
			txt.push "alter schema #{a.name}\n  owner to #{a.owner};"
		
		sql = @privileges.compare b.privileges
		txt.push sql if sql
		
		if txt.length is 0
			return null # no changes
		
		txt.join '\n'

class PGTable extends Table
	@create: (a) ->
		txt = []
		txt.push "create table #{a.name}(#{(col.definition for col in a.columns).join ', '}) with (oids=false);"
		
		sql = a.constraints.compare()
		txt.push sql if sql
		
		txt.push "alter table #{a.name}\n  owner to #{a.owner};"
		
		sql = a.privileges.compare()
		txt.push sql if sql
		
		sql = a.indexes.compare()
		txt.push sql if sql
		
		sql = a.triggers.compare()
		txt.push sql if sql
		
		txt.join '\n'
	
	@drop: (b) ->
		"drop table #{b.name};"
		
	compare: (b) ->
		txt = []
		
		sql = @columns.compare b.columns
		txt.push sql if sql
		
		sql = @constraints.compare b.constraints
		txt.push sql if sql

		if @owner isnt b.owner
			txt.push "alter table #{a.name}\n  owner to #{a.owner};"
		
		sql = @privileges.compare b.privileges
		txt.push sql if sql
		
		sql = @indexes.compare b.indexes
		txt.push sql if sql
		
		sql = @triggers.compare b.triggers
		txt.push sql if sql
		
		if txt.length is 0
			return null # no changes
		
		txt.join '\n'

class PGColumn extends Column
	@create: (a) ->
		"alter table #{a.table.name} add column #{a.definition};"
	
	@drop: (b) ->
		"alter table #{b.table.name} drop column #{b.name};"
		
	compare: (b) ->
		txt = []

		if @type isnt b.type
			txt.push "-- type of '#{@name}' changed from '#{b.type}' to '#{@type}'"
			txt.push "alter table #{@table.name} alter column #{@name} type #{@type} using #{@name}::#{@type};"
		
		if @default isnt b.default
			txt.push "-- default of '#{@name}' changed from '#{b.default}' to '#{@default}'"
			
			if @default
				txt.push "alter table #{@table.name} alter column #{@name} set default #{@default};"
			else
				txt.push "alter table #{@table.name} alter column #{@name} drop default;"
			
		if @notnull isnt b.notnull
			txt.push "-- not null of '#{@name}' changed from '#{if b.notnull then 'not null' else 'null'}' to '#{if @notnull then 'not null' else 'null'}'"
			
			if @notnull
				txt.push "alter table #{@table.name} alter column #{@name} set not null;"
			else
				txt.push "alter table #{@table.name} alter column #{@name} drop not null;"

		if txt.length is 0
			return null # no changes
		
		txt.join '\n'

class PGConstraint extends Constraint
	@create: (a) ->
		"alter table #{a.table.name} add constraint #{a.name} #{a.definition};"
	
	@drop: (b) ->
		"alter table #{b.table.name} drop constraint #{b.name};"
		
	compare: (b) ->
		txt = []

		if @definition isnt b.definition
			txt.push "-- recreate constraint '#{@name}'"
			txt.push "alter table #{@name} drop constraint #{@name};"
			txt.push "alter table #{@name} add constraint #{@name} #{@definition};"

		if txt.length is 0
			return null # no changes
		
		txt.join '\n'

class PGIndex extends Index
	@create: (a) ->
		"#{a.definition};"
	
	@drop: (b) ->
		"drop index #{b.name};"
		
	compare: (b) ->
		txt = []

		if @definition isnt b.definition
			txt.push "-- recreate index '#{@name}'"
			txt.push "drop index #{@name};"
			txt.push "#{@definition};"

		if txt.length is 0
			return null # no changes
		
		txt.join '\n'

class PGTrigger extends Trigger
	@create: (a) ->
		"#{a.definition};"
	
	@drop: (b) ->
		"drop trigger #{b.name};"
		
	compare: (b) ->
		txt = []

		if @definition isnt b.definition
			txt.push "-- recreate trigger '#{@name}'"
			txt.push "drop trigger #{@name};"
			txt.push "#{@definition};"

		if txt.length is 0
			return null # no changes
		
		txt.join '\n'

class PGFunction extends Function
	@create: (a) ->
		txt = []
		txt.push "#{a.definition};"
		txt.push "alter function #{a.name}\n  owner to #{a.owner};"
		txt.push a.privileges.compare()
		
		txt.join '\n'
	
	@drop: (b) ->
		"drop function #{b.name};"
	
	###
	Remove OUT parameters and name of IN parameters.
	
	@ignore
	###
	
	@normalizeName: (name) ->
		parts = name.match(/^([^\(]+)\(([^\)]*)\)$/)
		args = parts[2].split(/,\s/).filter (arg) ->
			if (/^OUT\s/).test arg then return false
			true
		
		args = args.map (arg) ->
			arg.substr arg.indexOf(' ') + 1
		
		"#{parts[1]}(#{args.join ', '})"
		
	compare: (b) ->
		txt = []

		if @definition isnt b.definition
			txt.push "drop function #{@name};" # drop or we might get error we can't update function when changes in arguments names
			txt.push "#{@definition};"
			txt.push "alter function #{@name}\n  owner to #{@owner};"
			txt.push @privileges.compare()
		
		else
			if @owner isnt b.owner
				txt.push "alter function #{@name}\n  owner to #{@owner};"
			
			sql = @privileges.compare b.privileges
			txt.push sql if sql
		
		if txt.length is 0
			return null # no changes
		
		txt.join '\n'

class PGView extends View
	@create: (a) ->
		txt = []
		txt.push "create or replace view #{a.name} as\n#{a.definition}"
		txt.push "alter table #{a.name}\n  owner to #{a.owner};"
		txt.push a.privileges.compare()
		
		txt.join '\n'
	
	@drop: (b) ->
		"drop view #{b.name};"
		
	compare: (b) ->
		txt = []

		if @definition isnt b.definition
			txt.push "create or replace view #{@name} as\n#{@definition}"
			txt.push "alter table #{@name}\n  owner to #{@owner};"
			txt.push @privileges.compare()
		
		else
			if @owner isnt b.owner
				txt.push "alter table #{@name}\n  owner to #{@owner};"
			
			sql = @privileges.compare b.privileges
			txt.push sql if sql
		
		if txt.length is 0
			return null # no changes
		
		txt.join '\n'

class PGPrivilege
	grantee: null
	grantor: null
	grants: null
	
	constructor: ->
		@grants = []
	
	@compare: (object, a, b = []) ->
		txt = []
		privileges = {}
		target = "#{if object.__type is 'view' then 'table' else object.__type} #{object.name}"

		for privilege in a
			privileges[privilege.grantee] =
				a: privilege
		
		for privilege in b
			privileges[privilege.grantee] ?= {}
			privileges[privilege.grantee].b = privilege

		for grantee, ab of privileges
			if ab.a and ab.b
				if ab.a.__string is ab.b.__string
					continue
				
				# reset privileges
				txt.push "-- resetting privileges for user '#{grantee}'"
				txt.push "revoke all on #{target}\n  from #{grantee};"
				
				withGrant = (grant.type for grant in ab.a.grants when grant.withgrant)
				withoutGrant = (grant.type for grant in ab.a.grants when not grant.withgrant)
					
				if withoutGrant.length
					txt.push "grant #{withoutGrant.join ', '} on #{target}\n  to #{grantee};"
				
				if withGrant.length
					txt.push "grant #{withGrant.join ', '} on #{target}\n  to #{grantee} with grant option;"
	
			else if ab.a
				withGrant = (grant.type for grant in ab.a.grants when grant.withgrant)
				withoutGrant = (grant.type for grant in ab.a.grants when not grant.withgrant)
					
				if withoutGrant.length
					txt.push "grant #{withoutGrant.join ', '} on #{target}\n  to #{grantee};"
				
				if withGrant.length
					txt.push "grant #{withGrant.join ', '} on #{target}\n  to #{grantee} with grant option;"
	
			else
				console.log object.__type, object.name, a, b
				
				txt.push "revoke all on #{target}\n  from #{grantee};"
		
		if txt.length is 0
			return null # no changes
		
		txt.join '\n'
	
	@fromACL: (acl, object) ->
		if not acl
			arr = []
		else
			arr = (PGPrivilege.parseACL item for item in acl.substr(1, acl.length - 2).split ',')
			
		arr.compare = PGPrivilege.compare.bind null, object, arr
		arr

	@parseACL = (acl) ->
		privilege = new PGPrivilege
		privilege.__string = acl

		c = '' # char
		i = -1 # index
		while i++ < acl.length
			c = acl.charAt i
			if c is '='
				privilege.grantee = acl.substr 0, i
				break
	
		while i++ < acl.length
			c = acl.charAt i
			if c is '\/'
				break
			
			if c is '*'
				privilege.grants[privilege.grants.length - 1].withgrant = true
	
			else
				privilege.grants.push
					type: PRIVILEGE[c]
					withgrant: false
		
		privilege.grantor = acl.substr i + 1
		privilege.grantee or= 'public'
		privilege

class PGRecord extends Record
	###
	@param {*} value
	@param {String} type
	@returns {*}
	###
	
	@castValue: (value, type) ->
		if not value? then return 'null'
		
		if 'function' is typeof value.toPostgres
			value = value.toPostgres()
		
		switch typeof value
			when 'string' then return PGRecord.sanitizeValue value
			when 'boolean' then return (if value then 'true' else 'false')
			when 'object'
				if Array.isArray value
					if (/\[\]$/).test type
						# postgres array
						"array[#{value.map((item) -> PGRecord.castValue item, type.substr(0, type.length - 2)).join ','}]"
					
					else
						# json array
						PGRecord.sanitizeValue JSON.stringify value
				
				else if Buffer.isBuffer value
					"E'\\\\x#{value.toString 'hex'}'"
				
				else if type in ['json', 'jsonb']
					PGRecord.sanitizeValue JSON.stringify value
				
				else
					return "unknown"
			
			else return String value
	
	###
	@param {*} value
	@param {String} type
	@returns {Boolean} Return true if both values are equal.
	###
	
	@compareValue: (a, b, type) ->
		if not a? and not b? then return true
		if not a? or not b? then return false
		
		if 'function' is typeof a.toPostgres
			a = a.toPostgres()
		
		if 'function' is typeof b.toPostgres
			b = b.toPostgres()
		
		if typeof a isnt typeof b
			return false
		
		switch typeof a
			when 'object'
				if Array.isArray(a) and Array.isArray(b)
					if a.length isnt b.length
						return false

					for index in [0...a.length]
						if not PGRecord.compareValue a[index], b[index]
							return false
					
					return true
				
				else if Buffer.isBuffer(a) and Buffer.isBuffer(b)
					return a.equals b
				
				else
					return JSON.stringify(a) is JSON.stringify(b)
				
			else return a is b
	
	###
	@param {Record} a
	@param {Record} b
	@returns {String}
	###
	
	@compareValues: (a, b, type) ->
		changes = []
		
		for cola in a.columns when not cola.primary
			colb = b.get cola.name
			
			if not PGRecord.compareValue cola.value, colb.value, cola.type
				#console.log 'COMPARE', cola.name, cola.value, colb.value
				changes.push "#{cola.name} = #{PGRecord.castValue cola.value, cola.type}"
		
		if changes.length is 0
			return null
		
		changes.join ', '
	
	@sanitizeValue: (value) ->
		"'#{value.replace(/'/g, '\'\'')}'"

	toInsert: ->
		columns = []
		values = []
		
		for col in @columns
			columns.push col.name
			values.push PGRecord.castValue col.value, col.type
		
		"insert into #{@table} (#{columns.join ', '}) values (#{values.join ', '});"
	
	toDelete: ->
		where = []
		for col in @columns when col.primary
			value = PGRecord.castValue col.value, col.type
			
			if value is 'null'
				where.push "#{col.name} is null"
			else
				where.push "#{col.name} = #{value}"
		
		"delete from #{@table} where #{where.join ' and '};"
	
	toUpdate: (b) ->
		sql = PGRecord.compareValues @, b
		if not sql then return null
		
		where = []
		for col in b.columns when col.primary
			value = PGRecord.castValue col.value, col.type
			
			if value is 'null'
				where.push "#{col.name} is null"
			else
				where.push "#{col.name} = #{value}"
		
		"update #{@table} set #{sql} where #{where.join ' and '};"

module.exports = PGDatabase