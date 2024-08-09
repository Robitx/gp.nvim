;; Top level function definitions
((module
   (function_definition 
     name: (identifier) @name ) @body
   (#not-has-ancestor? @body class_definition))
 (#set! "type" "function"))

;; Class member function definitions
((class_definition
  name: (identifier) @classname
  body: (block
          (function_definition 
            name: (identifier) @name ) @body))
 (#set! "type" "class_method"))


;; Class definitions
((class_definition
  name: (identifier) @name) @body
 (#set! "type" "class"))
