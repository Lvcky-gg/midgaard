package geo_style

// Symbol describes how a single feature or feature class should be drawn.
Symbol :: struct {
	color:       [4]f32,
	point_size:  f32,
	line_width:  f32,
	label_field: string,
}

// Filter selects features by attribute value.
Filter :: struct {
	field:    string,
	operator: Filter_Op,
	value:    string,
}

Filter_Op :: enum { Eq, Ne, Lt, Gt, Like }

// Style binds symbols and filters to a layer.
Style :: struct {
	layer_name: string,
	default_symbol: Symbol,
	rules: [dynamic]Style_Rule,
}

Style_Rule :: struct {
	filter: Filter,
	symbol: Symbol,
}
