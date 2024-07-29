(function_declaration
  name: (identifier) @name) @body

(function_declaration
  name: (dot_index_expression
          field: (identifier) @name)) @body

(function_declaration
  name: (dot_index_expression) @name) @body
