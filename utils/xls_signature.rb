# frozen_string_literal: true

# Helpers for the subset of XLS signature textproto used by test adapters.
def blocks(text, field)
  result = []
  pattern = /^\s*#{Regexp.escape(field)}\s*\{/
  offset = 0

  while (match = pattern.match(text, offset))
    start = match.end(0)
    depth = 1
    index = start
    while index < text.length && depth.positive?
      depth += 1 if text.getbyte(index) == "{".ord
      depth -= 1 if text.getbyte(index) == "}".ord
      index += 1
    end
    raise "unterminated #{field} block" unless depth.zero?

    result << text[start...(index - 1)]
    offset = index
  end
  result
end

def scalar(text, field)
  pattern = /^\s*#{Regexp.escape(field)}:\s*(?:"([^"]*)"|([^\s#]+))/
  match = pattern.match(text)
  raise "missing #{field}" unless match

  match[1] || match[2]
end

def identifier(name)
  return name if name.match?(/\A[A-Za-z_][A-Za-z0-9_$]*\z/)

  "\\#{name} "
end

