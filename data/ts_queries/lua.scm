;; Matches global and local function declarations
;;   function a_fn_name()
;;
;; This will only match on top level functions.
;; Specificadlly, this ignores the local function declarations.
;; We're only doing this because we're requiring the 
;; (file, function_name) pair to be unique in the database.
((chunk
   (function_declaration
	 name: (identifier) @name) @body)
 (#set! "type" "function"))

;; Matches function declaration using the dot syntax
;;   function a_table.a_fn_name()
((chunk
  (function_declaration 
	name: (dot_index_expression) @name) @body)
 (#set! "type" "function"))

;; Matches function declaration using the member function syntax
;;   function a_table:a_fn_name()
((chunk
  (function_declaration 
	name: (method_index_expression) @name) @body)
 (#set! "type" "function"))

;; Matches on:
;;   M.some_field = function() end
((chunk
  (assignment_statement 
	(variable_list 
	  name: (dot_index_expression) @name) 
	(expression_list 
	  value: (function_definition) @body)))
 (#set! "type" "function"))

;; Matches on:
;;   some_var = function() end
((chunk
  (assignment_statement 
	(variable_list 
	  name: (identifier) @name) 
	(expression_list 
	  value: (function_definition) @body)))
 (#set! "type" "function"))
