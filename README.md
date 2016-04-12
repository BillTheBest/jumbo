# jumbo

A tool to compare and synchronize PostgreSQL databases.

[![NPM Version][npm-image]][npm-url]

Synchronizes
* Users
* Schemas
* Tables
* Functions
* Views
* Data

## Installation

    npm install -g jumbo

## Usage

1. Create file `.jumbo.json`.

	```json
	{
		"web": {
			"port": 3000
		},
		"a": {
			"driver": "pg",
			"name": "server 1",
			"connectionString": "postgres://...:...@localhost:5432/database"
		},
		"b": {
			"driver": "pg",
			"name": "server 2",
			"connectionString": "postgres://...:...@localhost:5432/database"
		}
	}
	```

2. Run this command in the same directory.

	```shell
	jumbo
	```

3. And open your web browser with link displayed in the console.

4. Profit

## Additional configuration

You can spcify ignores for different kinds of objects.

```json
{
	"diff": {
		"tables": {
			"ignore": ["public.table1", "public.table2"]
		},
		"functions": {
			"ignore": ["public.*"]
		}
	}
}
```

To enable data synchronization, add `sync` section and specify tables to syncrhonize. Only `upstream` type is enabled atm.

```json
{
	"sync": {
		"public.country": {"type": "upstream"},
		"web.sessions": {"type": "upstream"}
	}
}
```

## TODO

- Dependencies

<a name="license" />
## License

Copyright (c) 2015 Integromat

The MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

[npm-image]: https://img.shields.io/npm/v/jumbo.svg?style=flat-square
[npm-url]: https://www.npmjs.com/package/jumbo
