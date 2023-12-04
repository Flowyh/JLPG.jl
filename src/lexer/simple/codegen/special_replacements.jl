using Parameters: @consts

@consts begin
  LEXER_SPECIAL_VARIABLES_REPLACEMENTS::Vector{Pair} = [
    raw"$$" => "__LEX__current_match()"
  ]

  LEXER_SPECIAL_FUNCTION_PREFIX = r"__LEX__"

  LEXER_SPECIAL_FUNCTIONS_PATTERNS = [LEXER_SPECIAL_FUNCTION_PREFIX * fn for fn in [
    r"at_end",
    r"main"
  ]]
end

function replace_special_variables_in_generated_lexer(
  generated_lexer::String
)::String
  for (special_variable, replacement) in LEXER_SPECIAL_VARIABLES_REPLACEMENTS
    generated_lexer = replace(generated_lexer, special_variable => replacement)
  end
  return generated_lexer
end

function replace_overloaded_functions_in_generated_lexer(
  generated_lexer::String
)::String
  for special_function in LEXER_SPECIAL_FUNCTIONS_PATTERNS
    found_overloads = findall(function_definition(special_function), generated_lexer)
    if length(found_overloads) <= 1
      continue
    end
    fn_name = match(function_name, generated_lexer[found_overloads[1]])[:name]
    fn_name = replace(fn_name, LEXER_SPECIAL_FUNCTION_PREFIX => "")

    # Replace code between start and end for # <<: OVERLOADED :>>
    to_replace   = SPECIAL_FUNCTION_START(fn_name) *
                   r"[\S\s]*" *
                   SPECIAL_FUNCTION_END(fn_name)
    replaced_msg = SPECIAL_FUNCTION_OVERLOAD_MSG(fn_name)

    generated_lexer = replace(generated_lexer, to_replace => replaced_msg)
  end

  return generated_lexer
end
