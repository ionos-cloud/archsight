import Prism from 'prismjs'

// Prism grammar for the .asd diagram DSL (see docs/diagram.md and lib/archsight/diagram/parser),
// registered under the name the code block language picker and ```asd fences use. Lexical's code
// highlighter looks languages up in this shared Prism instance.
const CONTAINERS = 'group|layer|stack|boundary'
const LEAVES = 'component|application|api|database|queue|actor|file'
const OTHER = 'dataflow|hop|branch|theme|legend'
const ATTRIBUTES = 'label|tint|link|resource|extend|shape|gap|no-gap|no-extend|ranks|columns|style|relation|color'

// keyword and attribute names are only words when not part of a longer identifier (ids may contain - . /)
const word = (names) => new RegExp(`(?<![\\w./-])(?:${names})(?![\\w./-])`)

Prism.languages.asd = {
  comment: /#.*/,
  string: { pattern: /"(?:[^"\\]|\\[\s\S])*"/, greedy: true },
  keyword: word(`${CONTAINERS}|${LEAVES}|${OTHER}`),
  property: word(ATTRIBUTES),
  operator: /<->|->|--/,
  punctuation: /[{};]/,
}

export default Prism
