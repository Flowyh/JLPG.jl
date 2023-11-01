using Parameters: @consts

@enum ParserSection definitions productions code
@enum ParserSpecialDefinition section code_block option token type start production production_alt comment

@consts begin
  ParserSectionDelimiter::String = "%%"
  ParserCodeBlockStart::String = "%{"
  ParserCodeBlockEnd::String = "%}"

  PARSER_SECTION_REGEX = r"%%"
  PARSER_CODE_BLOCK_REGEX = r"%{((?s:.)*?)%}"
  PARSER_OPTION_REGEX = r"%option[ \t]+((?:\w+ ?)+)"
  TOKEN_REGEX = r"%token[ \t]+(?<name>[A-Z0-9_-]+)(?:[ \t]+\"(?<alias>.+)\")?"
  TYPE_REGEX = r"%type[ \t]+<(?<type>\w+)>(?:[ \t]+(?<symbol>\w+))?"
  START_REGEX = r"%start[ \t]+(?<symbol>.+)"
  PRODUCTION_REGEX = r"(?<lhs>[a-z0-9_-]+)\s+->\s+(?<production>[A-Za-z0-9_ \t-]+?)\s+{(?<action>(?s:.)*?)}"
  EMPTY_PRODUCTION_REGEX = r"(?<lhs>[a-z0-9_-]+)\s+->\s+(?<production>.+)"
  PRODUCTION_ALT_REGEX = r"\|\s+(?<production>.+)\s+?{(?<action>(?s:.)*?)}"
  EMPTY_PRODUCTION_ALT_REGEX = r"\|\s+(?<production>.+)"
  PARSER_COMMENT_REGEX = r"#=[^\n]*=#\n?"

  SpecialDefinitionPatterns::Vector{Pair{ParserSpecialDefinition, Regex}} = [
    section => PARSER_SECTION_REGEX,
    code_block => PARSER_CODE_BLOCK_REGEX,
    option => PARSER_OPTION_REGEX,
    token => TOKEN_REGEX,
    type => TYPE_REGEX,
    start => START_REGEX,
    production => PRODUCTION_REGEX,
    production => EMPTY_PRODUCTION_REGEX,
    production_alt => PRODUCTION_ALT_REGEX,
    production_alt => EMPTY_PRODUCTION_ALT_REGEX,
    comment => PARSER_COMMENT_REGEX
  ]
end

# Structure of a definition file:
#
# definitions/flags
# %%
# grammar productions
# %%
# user code
#
# Blocks enclosed with %{ and %} are copied to the output file (in the same order).

function read_parser_definition_file(
  path::String
)::Parser
  parser::Union{Parser, Nothing} = nothing
  open(path) do file
    parser = _read_parser_definition_file(file)
  end

  return parser::Parser
end

function _next_parser_section(
  current::ParserSection
)::ParserSection
  if current == definitions
    return productions
  elseif current == productions
    return code
  end
end

function _parser_section_guard(
  current::ParserSection,
  expected::ParserSection,
  err_msg::String
)
  if current != expected
    error(err_msg)
  end
end

islowercased(str::String)::Bool = ismatch(r"^[a-z0-9_-]+$", str)
isuppercased(str::String)::Bool = ismatch(r"^[A-Z0-9_-]+$", str)

function _split_production_string(
  production::String
)::Tuple{Vector{Symbol}, Vector{Symbol}, Vector{Symbol}}
  sanitized = strip(production)
  symbols = split(sanitized, r"\s+")
  terminals::Vector{Symbol} = []
  nonterminals::Vector{Symbol} = []
  for _symbol in symbols
    if islowercased(_symbol)
      push!(nonterminals, Symbol(_symbol))
    elseif isuppercased(_symbol)
      push!(terminals, Symbol(_symbol))
    else
      error("Symbol in production has to be either lowercase or uppercase (got $_symbol)")
    end
  end
  return (Symbol.(symbols), terminals, nonterminals)
end

# TODO: Better error signaling
function _read_parser_definition_file(
  file::IOStream
)::Parser
  current_section = definitions
  current_production_lhs::Union{Symbol, Nothing} = nothing
  terminals::Set{Symbol} = Set()
  nonterminals::Set{Symbol} = Set()
  starting::Union{Symbol, Nothing} = nothing
  productions::Dict{Symbol, ParserProduction}  = Dict()
  symbol_types::Dict{Symbol, Symbol} = Dict()
  tokens::Set{Symbol} = Set()
  token_aliases::Dict{Symbol, Symbol} = Dict()
  code_blocks::Vector{String} = []
  options = ParserOptions() # TODO: Fill if needed

  text::String = read(file, String)
  cursor::Int = 1

  while cursor <= length(text)
    did_match::Bool = false
    for (definition, pattern) in SpecialDefinitionPatterns
      matched = findnext(pattern, text, cursor)
      if matched !== nothing || matched.start != cursor
        continue
      end
      m = match(pattern, text[matched])

      if definition == section
        current_section = _next_parser_section(current_section)
      elseif definition == code_block
        code_block_txt = text[matched]
        push!(code_blocks, strip(code_block_txt[4:end-2])) # Omit %{\n and %}
      elseif definition == option
        _parser_section_guard(current_section, definitions, "Option $(text[matched]) outside of definitions section")
        # TODO: Fill if needed
      elseif definition == token
        _parser_section_guard(current_section, definitions, "Token definition $(text[matched]) outside of definitions section")

        t, a = Symbol(m[:name]), Symbol(m[:alias])
        if t in tokens || a in token_aliases
          error("Token $(text[matched]) already defined")
        end
        push!(tokens, t)
        push!(tokens, a)

        if a !== nothing
          token_aliases[a] = t
          token_aliases[t] = a
        end
      elseif defintion == type
        _parser_section_guard(current_section, definitions, "Type definition $(text[matched]) outside of definitions section")
        symbol_types[Symbol(m[:symbol])] = Symbol(m[:type])
      elseif definition == start
        _parser_section_guard(current_section, productions, "Start definition $(text[matched]) outside of productions section")
        if starting !== nothing
          error("Start symbol already defined")
        end
        starting = Symbol(m[:symbol])
      elseif definition == production
        _parser_section_guard(current_section, productions, "Production $(text[matched]) outside of productions section")
        current_production_lhs = Symbol(m[:lhs])

        if current_production_lhs in productions
          error("Production $(text[matched]) already defined")
        end

        if !islowercased(current_production_lhs)
          error("Production LHS has to be lowercase, because it is a nonterminal (got $(m[:lhs]))")
        end

        # First production is considered as the starting production, unless specified otherwise
        if starting === nothing
          starting = current_production_lhs
        end

        _production, _terminals, _nonterminals = _split_production_string(m[:production])
        push!(_nonterminals, current_production_lhs)

        union!(terminals, _terminals)
        union!(nonterminals, _nonterminals)

        return_type = get(symbol_types, current_production_lhs, Symbol("String"))

        productions[current_production_lhs] = ParserProduction(
          current_production_lhs,
          _production,
          m[:action],
          return_type
        )
      elseif definition == production_alt
        _parser_section_guard(current_section, productions, "Production alternative $(text[matched]) outside of productions section")

        _production, _terminals, _nonterminals = _split_production_string(m[:production])
        push!(_nonterminals, current_production_lhs)

        union!(terminals, _terminals)
        union!(nonterminals, _nonterminals)
get
        return_type = (symbol_types, current_production_lhs, Symbol("String"))

        productions[current_production_lhs] = ParserProduction(
          current_production_lhs,
          _production,
          m[:action],
          return_type
        )
      end

      cursor += length(matched)
      did_match = true
      break
    end
  end

  return Parser(
    terminals,
    nonterminals,
    starting::Symbol,
    productions,
    symbol_types,
    tokens,
    token_aliases,
    code_blocks,
    options
  )
end
