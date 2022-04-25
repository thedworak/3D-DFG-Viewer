import jsdoc from 'jsdoc-api';
import hbs from 'handlebars';
import fs from 'fs';

const TEMPLATE = 'scripts/api.hbs.md';
const OUTPUT = 'API.md';
const JSDOC_INPUT = 'src/**/*.js';

const WRITE = !!process.argv.slice( 2 ).find( v => v === '--write' );

// url prefix for view source links, needs trailing slash
const REPO = 'https://github.com/georgealways/gui/blob/master/';

// sort by kind as opposed to order of definition
const KIND_SORT = [ 'class', 'function', 'member' ];

// put members that start with special chars at the end
const ALPHABET_SORT = 'abcdefghijklmnopqrstuvwxyz$_'.split( '' );

// explicit index order, anything not in here goes to the end
const TOP_LEVEL_SORT = [ 'GUI', 'Controller' ];

// begin script!

// jsdoc data is decorated with indexname, signature, viewsource link etc.
// then collected here
const transformed = [];

// classes are collected as top level entries for the index
// then stored in this map by longname
const topLevel = {};

jsdoc.explainSync( { files: JSDOC_INPUT } )
	.filter( v => v.undocumented !== true )
	.filter( v => v.kind !== 'package' )
	.filter( v => v.kind !== 'module' )
	.forEach( transform );

function transform( v ) {

	if ( v.access === 'protected' ) return;

	forEachRecursive( v, ( object, key, value ) => {

		if ( typeof value === 'string' ) {

			// replace local directories with path to github
			value = value.replace( process.cwd(), REPO.substr( 0, REPO.length - 1 ) );

			// jsdoc gets a little too excited about modules
			value = value.replace( /^module:/, '' );

			// does strange stuff with multitype arrays
			value = value.replace( /Array\.<\(?([^)]+)\)?>/g, ( _, c ) => `Array<${c}>` );

			// terser syntax for single type arrays
			value = value.replace( /Array<([^|]*)>/, ( _, c ) => `${c}[]` );

		}

		object[ key ] = value;

	} );

	v.indexname = v.name;

	if ( v.kind === 'function' && v.scope === 'instance' ) {

		v.signature = `${v.memberof.toLowerCase()}.**${v.name}**`;

		v.indexname = `**${v.name}**`;

		if ( v.params ) {
			v.indexname = `**${v.name}()**`;
			v.parens = paramsToSignature( v.params );
		}

		if ( v.returns ) {

			const type = v.returns[ 0 ].type.names[ 0 ];

			v.returntype = type;
			v.indextype = '→ ' + type;

		} else {

			v.indextype = ': void';

		}

	} else if ( v.kind === 'class' ) {

		topLevel[ v.longname ] = v;

		if ( v.params ) {
			v.signature = `new **${v.name}**`;
			v.parens = paramsToSignature( v.params );

			v.indexname = '**constructor**';

			// collect it
			v.memberof = v.longname;

			v.longname += '#constructor';

		}

		// sometimes get classdesc instead of regular desc for classes
		v.description = v.description || v.classdesc;

		v.children = [];

	} else if ( v.kind === 'member' && v.scope === 'instance' ) {

		v.signature = `${v.memberof.toLowerCase()}.**${v.name}**`;

		if ( v.type ) {
			const type = ': ' + v.type.names.join( '|' );
			v.indextype = type;
			v.parens = ' ' + type;
		}

	}

	if ( v.params && v.params.length > 3 && v.signature ) {

		const arg0 = v.params[ 0 ].name;
		const rest = v.params.slice( 1 );
		const prefix = arg0 + '.';

		if ( rest.every( v => v.name.startsWith( prefix ) ) ) {

			v.parens = `( { ${rest.map( v => v.name.replace( prefix, '' ) ).join( ', ' )} } )`;
			v.params.splice( 0, 1 );
			v.params.forEach( p => p.name = p.name.replace( prefix, '' ) );

		} else {

			const single = p => p.optional ? '[' + p.name + ']' : p.name;
			v.parens = `( ${v.params.map( single ).join( ', ' )} )`;

		}

	}

	// view source url
	const joined = v.meta.path + '/' + v.meta.filename;
	v.viewsource = `${joined}#L${v.meta.lineno}`;
	v.definedat = joined.replace( REPO, '' ) + ':' + v.meta.lineno;

	// clogging up my debug
	delete v.comment;
	delete v.meta;

	transformed.push( v );

}

// associate transformed children with their memberof types
transformed.forEach( v => {

	if ( v.memberof && v.memberof in topLevel ) {

		const parent = topLevel[ v.memberof ];

		if ( v.children ) {
			// prevent circular structure in json
			v = JSON.parse( JSON.stringify( v ) );
			delete v.children;
		}

		parent.children.push( v );

	}

} );

// done processing, get an array for handlebars
const jsdocData = Object.values( topLevel );

// sort topLevel by explicit order
jsdocData.sort( ( a, b ) => {
	return customComparison( TOP_LEVEL_SORT, a.name, b.name );
} );

// sort children by kind, then alphabetically with special chars at the end
jsdocData.forEach( t => {
	t.children.sort( childSort( Array.from( t.children ) ) );
} );

const output = hbs.compile( fs.readFileSync( TEMPLATE ).toString() )
	.call( undefined, { jsdocData } )
	.replace( /\n{2,}/g, '\n\n' ); // clean up extra whitespace

// write to markdown
if ( WRITE ) {
	fs.writeFileSync( OUTPUT, output );
}

// or give this to homepage.js so it can print to browser console for debug
export default jsdocData;

function childSort( originalOrder ) {

	return function( a, b ) {

		const kindComparison = customComparison( KIND_SORT, a.kind, b.kind );
		if ( kindComparison !== 0 ) return kindComparison;

		if ( a.kind === 'member' ) {

			const alphabetComparison = customComparison( ALPHABET_SORT, a.name[ 0 ], b.name[ 0 ] );

			if ( alphabetComparison !== 0 ) return alphabetComparison;

			return a.name.localeCompare( b.name );

		} else {

			return customComparison( originalOrder, a, b );

		}

	};

}

function forEachRecursive( object, callback ) {
	for ( let key in object ) {
		const value = object[ key ];
		if ( Object( value ) === value ) {
			forEachRecursive( value, callback );
		} else {
			callback( object, key, value );
		}
	}
}

function customComparison( ordering, a, b ) {
	let ai = ordering.indexOf( a );
	let bi = ordering.indexOf( b );
	if ( ai === -1 ) ai = Infinity;
	if ( bi === -1 ) bi = Infinity;
	return ai - bi;
}

function paramsToSignature( params ) {

	if ( params.length === 0 ) {
		return '()';
	}

	const paramList = params
		.map( singleParamToSignature )
		.join( ', ' );

	return `( ${paramList} )`;

}

function singleParamToSignature( param ) {

	let name = param.name;

	const hasDefault = param.defaultvalue !== undefined;

	if ( hasDefault ) {
		name += '=' + param.defaultvalue;
	}

	if ( !hasDefault &&
		param.type &&
		param.type.names[ 0 ] !== '*' &&
		param.type.names[ 0 ] !== 'any' ) {
		// name += ': ' + param.type.names.join( '|' );
	}

	if ( param.optional ) {
		name = `[${name}]`;
	}

	return name;

}

// function singleParamToSignature( param ) {

// 	let name = param.type.names.join( '|' );

// 	if ( param.defaultvalue !== undefined ) {
// 		name = param.name + '=' + param.defaultvalue;
// 	}

// 	if ( param.defaultvalue === undefined && param.optional ) {
// 		name = `[${name}]`;
// 	}

// 	return name;

// }
