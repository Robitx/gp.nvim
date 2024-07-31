;; Matches global and local function declarations
(function_declaration
  name: (identifier) @name) @body

;; Matches on:
;;   M.some_fn = function() end
(assignment_statement 
  (variable_list 
    name: (dot_index_expression) @name) 
  (expression_list 
    value: (function_definition) @body))
