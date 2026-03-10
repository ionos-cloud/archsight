import hljs from 'highlight.js'

export function highlightCodeBlocks(container) {
  if (!container) return

  // Handle kramdown/rouge output: <div class="language-yaml highlighter-rouge"><div class="highlight"><pre class="highlight"><code>...</code></pre></div></div>
  // Extract language from wrapper div, set it on the code element, and strip rouge spans so hljs can re-highlight
  container.querySelectorAll('div[class*="language-"].highlighter-rouge pre.highlight code').forEach(el => {
    const wrapper = el.closest('.highlighter-rouge')
    const lang = [...wrapper.classList].find(c => c.startsWith('language-'))?.replace('language-', '')
    if (lang) {
      el.className = `language-${lang}`
      el.textContent = el.textContent // strip rouge <span> markup
    }
  })

  // Highlight all code blocks with a language class (both standard markdown and rouge-converted)
  container.querySelectorAll('pre code[class*="language-"]').forEach(el => {
    hljs.highlightElement(el)
  })
}
