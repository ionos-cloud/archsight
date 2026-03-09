<script setup>
import { ref, watch, onUnmounted } from 'vue'
import { createEditor, $getRoot, $getSelection, $isRangeSelection, FORMAT_TEXT_COMMAND, $createTextNode, $createParagraphNode } from 'lexical'
import { registerRichText, HeadingNode, QuoteNode, $createHeadingNode, $createQuoteNode } from '@lexical/rich-text'
import { registerHistory, createEmptyHistoryState } from '@lexical/history'
import { $convertFromMarkdownString, $convertToMarkdownString, TRANSFORMERS } from '@lexical/markdown'
import { ListNode, ListItemNode, registerList, INSERT_ORDERED_LIST_COMMAND, INSERT_UNORDERED_LIST_COMMAND } from '@lexical/list'
import { CodeNode, CodeHighlightNode, registerCodeHighlighting, $createCodeNode, $isCodeNode } from '@lexical/code'
import { LinkNode, $createLinkNode, $isLinkNode } from '@lexical/link'
import { $setBlocksType } from '@lexical/selection'

const props = defineProps({
  modelValue: String,
  visible: Boolean,
})

const emit = defineEmits(['update:modelValue', 'close'])

const editorRoot = ref(null)
let editor = null
const codeLang = ref(null)

const CODE_LANGUAGES = [
  'javascript', 'typescript', 'ruby', 'python', 'html', 'css', 'json', 'yaml',
  'bash', 'sql', 'go', 'rust', 'java', 'mermaid', 'markdown', 'text',
]

function initEditor() {
  if (editor || !editorRoot.value) return

  editor = createEditor({
    namespace: 'ArchsightMarkdownEditor',
    nodes: [HeadingNode, QuoteNode, ListNode, ListItemNode, CodeNode, CodeHighlightNode, LinkNode],
    onError: (error) => console.error('Lexical Error:', error),
    theme: {
      paragraph: 'lexical-paragraph',
      heading: { h1: 'lexical-h1', h2: 'lexical-h2', h3: 'lexical-h3' },
      list: { ul: 'lexical-ul', ol: 'lexical-ol', listitem: 'lexical-li' },
      quote: 'lexical-quote',
      code: 'lexical-code',
      codeHighlight: {
        atrule: 'tokenAttr', attr: 'tokenAttr', boolean: 'tokenProperty',
        builtin: 'tokenSelector', cdata: 'tokenComment', char: 'tokenSelector',
        class: 'tokenFunction', 'class-name': 'tokenFunction', comment: 'tokenComment',
        constant: 'tokenProperty', deleted: 'tokenProperty', doctype: 'tokenComment',
        entity: 'tokenOperator', function: 'tokenFunction', important: 'tokenVariable',
        inserted: 'tokenSelector', keyword: 'tokenAttr', namespace: 'tokenVariable',
        number: 'tokenProperty', operator: 'tokenOperator', prolog: 'tokenComment',
        property: 'tokenProperty', punctuation: 'tokenPunctuation', regex: 'tokenVariable',
        selector: 'tokenSelector', string: 'tokenSelector', symbol: 'tokenProperty',
        tag: 'tokenProperty', url: 'tokenOperator', variable: 'tokenVariable',
      },
      link: 'lexical-link',
      text: {
        bold: 'lexical-bold', italic: 'lexical-italic', underline: 'lexical-underline',
        strikethrough: 'lexical-strikethrough', code: 'lexical-text-code',
      },
    },
  })

  editor.setRootElement(editorRoot.value)
  registerRichText(editor)
  registerList(editor)
  registerCodeHighlighting(editor)
  registerHistory(editor, createEmptyHistoryState(), 300)

  // Track selection to show/hide code language
  editor.registerUpdateListener(() => {
    editor.getEditorState().read(() => {
      const selection = $getSelection()
      if ($isRangeSelection(selection)) {
        const nodes = selection.getNodes()
        for (const node of nodes) {
          const parent = node.getParent()
          if ($isCodeNode(parent)) { codeLang.value = parent.getLanguage() || ''; return }
          if ($isCodeNode(node)) { codeLang.value = node.getLanguage() || ''; return }
        }
      }
      codeLang.value = null
    })
  })
}

watch(() => props.visible, (v) => {
  if (v) {
    // Use nextTick-like delay to ensure DOM is ready after v-if renders
    setTimeout(() => {
      // v-if destroys the DOM on close, so dispose old editor and create fresh
      if (editor) {
        editor.setRootElement(null)
        editor = null
      }
      initEditor()
      if (editor) {
        editor.update(() => {
          $getRoot().clear()
          $convertFromMarkdownString(props.modelValue || '', TRANSFORMERS)
        })
      }
    }, 0)
  }
})

function save() {
  if (!editor) return
  editor.update(() => {
    const markdown = $convertToMarkdownString(TRANSFORMERS)
    emit('update:modelValue', markdown)
    emit('close')
  })
}

function formatText(format) {
  if (editor) editor.dispatchCommand(FORMAT_TEXT_COMMAND, format)
}

function formatBlock(type) {
  if (!editor) return
  if (type === 'bullet') { editor.dispatchCommand(INSERT_UNORDERED_LIST_COMMAND, undefined); return }
  if (type === 'number') { editor.dispatchCommand(INSERT_ORDERED_LIST_COMMAND, undefined); return }
  editor.update(() => {
    const selection = $getSelection()
    if (!$isRangeSelection(selection)) return
    if (['h1', 'h2', 'h3'].includes(type)) $setBlocksType(selection, () => $createHeadingNode(type))
    else if (type === 'quote') $setBlocksType(selection, () => $createQuoteNode())
    else if (type === 'paragraph') $setBlocksType(selection, () => $createParagraphNode())
  })
}

function insertCodeBlock() {
  if (!editor) return
  editor.update(() => {
    const selection = $getSelection()
    if ($isRangeSelection(selection)) {
      const node = $createCodeNode('')
      selection.insertNodes([node])
      node.select()
    }
  })
}

function setCodeLanguage(lang) {
  if (!editor) return
  editor.update(() => {
    const selection = $getSelection()
    if (!$isRangeSelection(selection)) return
    for (const node of selection.getNodes()) {
      const parent = node.getParent()
      if ($isCodeNode(parent)) { parent.setLanguage(lang); return }
      if ($isCodeNode(node)) { node.setLanguage(lang); return }
    }
  })
}

function insertLink() {
  const url = prompt('Enter URL:', 'https://')
  if (url === null) return
  if (!editor) return
  editor.update(() => {
    const selection = $getSelection()
    if (!$isRangeSelection(selection)) return
    if (url === '') {
      selection.getNodes().forEach(node => {
        const parent = node.getParent()
        if ($isLinkNode(parent)) {
          parent.getChildren().forEach(c => parent.insertBefore(c))
          parent.remove()
        }
      })
    } else {
      const text = selection.getTextContent() || url
      const linkNode = $createLinkNode(url)
      linkNode.append($createTextNode(text))
      selection.insertNodes([linkNode])
    }
  })
}

function onKeydown(e) {
  if (e.key === 'Escape') emit('close')
}

onUnmounted(() => {
  if (editor) {
    editor.setRootElement(null)
    editor = null
  }
})
</script>

<template>
  <div v-if="visible" id="markdown-editor-overlay" @keydown="onKeydown">
    <div class="markdown-editor-backdrop" @click="$emit('close')"></div>
    <div class="markdown-editor-panel">
      <div class="lexical-toolbar">
        <button class="toolbar-btn" type="button" @click="formatText('bold')" title="Bold (Ctrl+B)">
          <i class="iconoir-bold"></i>
        </button>
        <button class="toolbar-btn" type="button" @click="formatText('italic')" title="Italic (Ctrl+I)">
          <i class="iconoir-italic"></i>
        </button>
        <button class="toolbar-btn" type="button" @click="formatText('strikethrough')" title="Strikethrough">
          <i class="iconoir-strikethrough"></i>
        </button>
        <button class="toolbar-btn" type="button" @click="formatText('code')" title="Inline Code">
          <i class="iconoir-code"></i>
        </button>
        <div class="toolbar-divider"></div>
        <button class="toolbar-btn" type="button" @click="formatBlock('h1')" title="Heading 1">H1</button>
        <button class="toolbar-btn" type="button" @click="formatBlock('h2')" title="Heading 2">H2</button>
        <button class="toolbar-btn" type="button" @click="formatBlock('h3')" title="Heading 3">H3</button>
        <div class="toolbar-divider"></div>
        <button class="toolbar-btn" type="button" @click="formatBlock('bullet')" title="Bullet List">
          <i class="iconoir-list"></i>
        </button>
        <button class="toolbar-btn" type="button" @click="formatBlock('number')" title="Numbered List">
          <i class="iconoir-numbered-list-left"></i>
        </button>
        <button class="toolbar-btn" type="button" @click="formatBlock('quote')" title="Quote">
          <i class="iconoir-quote"></i>
        </button>
        <div class="toolbar-divider"></div>
        <button class="toolbar-btn" type="button" @click="insertLink()" title="Insert Link">
          <i class="iconoir-link"></i>
        </button>
        <div class="toolbar-divider"></div>
        <button class="toolbar-btn" type="button" @click="insertCodeBlock()" title="Code Block">
          <i class="iconoir-code-brackets"></i>
        </button>
        <select
          v-if="codeLang !== null"
          class="toolbar-select"
          :value="codeLang"
          @change="setCodeLanguage($event.target.value)"
          title="Code Language"
        >
          <option value="">Language...</option>
          <option v-for="lang in CODE_LANGUAGES" :key="lang" :value="lang">
            {{ lang.charAt(0).toUpperCase() + lang.slice(1) }}
          </option>
        </select>
        <div class="toolbar-spacer"></div>
        <button class="secondary toolbar-action" type="button" @click="$emit('close')">Cancel</button>
        <button class="toolbar-action" type="button" @click="save">Save</button>
      </div>
      <div class="lexical-editor-container">
        <div ref="editorRoot" id="lexical-editor-root" contenteditable="true"></div>
      </div>
    </div>
  </div>
</template>

<style scoped>
#markdown-editor-overlay {
  position: fixed;
  top: 0;
  right: 0;
  bottom: 0;
  left: 0;
  z-index: 1000;
}

.markdown-editor-backdrop {
  position: absolute;
  top: 0;
  right: 0;
  bottom: 0;
  left: 0;
  background-color: rgba(0, 0, 0, 0.5);
}

.markdown-editor-panel {
  position: absolute;
  top: 2rem;
  right: 2rem;
  bottom: 2rem;
  left: 2rem;
  display: flex;
  flex-direction: column;
  border-radius: 12px;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3), 0 2px 8px rgba(0, 0, 0, 0.2);
  background-color: var(--card-background-color, #fff);
  overflow: hidden;
}

.lexical-toolbar {
  display: flex;
  align-items: center;
  gap: 0.25rem;
  padding: 0.5rem 1rem;
  background-color: var(--card-background-color, #fff);
  flex-wrap: wrap;
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
  z-index: 1;
}

.toolbar-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 2rem;
  height: 2rem;
  padding: 0 0.5rem;
  margin: 0;
  background: transparent;
  border: 1px solid transparent;
  border-radius: var(--border-radius);
  color: var(--color);
  font-size: 0.85rem;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.15s ease;
}

.toolbar-btn:hover {
  background-color: var(--muted-border-color);
  border-color: var(--muted-border-color);
}

.toolbar-btn:active {
  background-color: var(--primary);
  border-color: var(--primary);
  color: var(--primary-inverse);
}

.toolbar-btn i {
  font-size: 1.1rem;
}

.toolbar-divider {
  width: 1px;
  height: 1.5rem;
  margin: 0 0.5rem;
  background-color: var(--muted-border-color);
}

.toolbar-spacer {
  flex: 1;
}

.toolbar-action {
  padding: 0.4rem 0.75rem;
  margin: 0;
  font-size: 0.85rem;
}

.toolbar-select {
  height: 2rem;
  width: auto;
  min-width: 130px;
  max-width: 180px;
  padding: 0 0.75rem;
  margin: 0;
  font-size: 0.85rem;
  border: 1px solid var(--pico-muted-border-color, #e4e4e7);
  border-radius: var(--pico-border-radius, 0.375rem);
  background-color: transparent;
  color: var(--pico-color, inherit);
  cursor: pointer;
  flex-shrink: 0;
}

.toolbar-select:hover {
  border-color: var(--pico-primary, #1e88e5);
}

.toolbar-select:focus {
  outline: none;
  border-color: var(--pico-primary, #1e88e5);
}

.lexical-editor-container {
  flex: 1;
  display: flex;
  flex-direction: column;
  min-height: 0;
  position: relative;
}

#lexical-editor-root {
  flex: 1;
  min-height: 0;
  padding: 1rem 1.5rem;
  font-family: var(--font-family);
  line-height: 1.6;
  overflow-y: auto;
  position: relative;
}

#lexical-editor-root:focus {
  outline: none;
}

#lexical-editor-root :deep(p) {
  margin: 0 0 0.75rem 0;
}

#lexical-editor-root :deep(p:last-child) {
  margin-bottom: 0;
}

#lexical-editor-root :deep(h1),
#lexical-editor-root :deep(h2),
#lexical-editor-root :deep(h3),
#lexical-editor-root :deep(h4) {
  margin: 1rem 0 0.5rem 0;
  font-weight: 600;
}

#lexical-editor-root :deep(h1:first-child),
#lexical-editor-root :deep(h2:first-child),
#lexical-editor-root :deep(h3:first-child) {
  margin-top: 0;
}

#lexical-editor-root :deep(ul),
#lexical-editor-root :deep(ol) {
  margin: 0.5rem 0;
  padding-left: 1.5rem;
}

#lexical-editor-root :deep(li) {
  margin: 0.25rem 0;
}

#lexical-editor-root :deep(blockquote) {
  margin: 0.75rem 0;
  padding: 0.5rem 1rem;
  border-left: 3px solid var(--pico-muted-border-color, #e4e4e7);
  color: var(--pico-muted-color, #71717a);
  font-style: italic;
}

#lexical-editor-root :deep(code) {
  padding: 0.15rem 0.35rem;
  background-color: var(--code-background-color, #f4f4f5);
  border: 1px solid var(--pico-muted-border-color, #e4e4e7);
  border-radius: 3px;
  font-family: var(--pico-font-family-monospace, monospace);
  font-size: 0.9em;
}

#lexical-editor-root :deep(pre) {
  margin: 0.75rem 0;
  padding: 1rem;
  background-color: var(--code-background-color);
  border-radius: var(--border-radius);
  overflow-x: auto;
  position: relative;
}

#lexical-editor-root :deep(pre code) {
  padding: 0;
  background: none;
}

#lexical-editor-root :deep(.lexical-code) {
  position: relative;
  display: block;
  margin: 0.75rem -1.5rem;
  padding: 1rem 1.5rem;
  min-width: calc(100% + 3rem);
  background-color: var(--code-background-color, #f4f4f5);
  border-top: 1px solid var(--pico-muted-border-color, #e4e4e7);
  border-bottom: 1px solid var(--pico-muted-border-color, #e4e4e7);
  border-radius: 0;
  font-family: var(--pico-font-family-monospace, monospace);
  font-size: 0.9em;
  line-height: 1.5;
  overflow-x: auto;
  white-space: pre;
  tab-size: 2;
  box-sizing: border-box;
}

/* Code highlight token colors */
#lexical-editor-root :deep(.lexical-code .tokenComment) { color: #6a737d; }
#lexical-editor-root :deep(.lexical-code .tokenPunctuation) { color: #24292e; }
#lexical-editor-root :deep(.lexical-code .tokenProperty) { color: #005cc5; }
#lexical-editor-root :deep(.lexical-code .tokenSelector) { color: #032f62; }
#lexical-editor-root :deep(.lexical-code .tokenOperator) { color: #005cc5; }
#lexical-editor-root :deep(.lexical-code .tokenAttr) { color: #d73a49; }
#lexical-editor-root :deep(.lexical-code .tokenVariable) { color: #e36209; }
#lexical-editor-root :deep(.lexical-code .tokenFunction) { color: #6f42c1; }

#lexical-editor-root :deep(a) {
  color: var(--primary);
  text-decoration: underline;
}

#lexical-editor-root :deep(.lexical-link) {
  color: var(--pico-primary, #1e88e5);
  text-decoration: underline;
  cursor: pointer;
}

#lexical-editor-root :deep(.lexical-link:hover) {
  text-decoration: none;
}

#lexical-editor-root :deep(strong),
#lexical-editor-root :deep(.lexical-bold) { font-weight: 700; }

#lexical-editor-root :deep(em),
#lexical-editor-root :deep(.lexical-italic) { font-style: italic; }

#lexical-editor-root :deep(u),
#lexical-editor-root :deep(.lexical-underline) { text-decoration: underline; }

#lexical-editor-root :deep(s),
#lexical-editor-root :deep(.lexical-strikethrough) { text-decoration: line-through; }

@media (prefers-color-scheme: dark) {
  .markdown-editor-panel {
    background-color: var(--card-background-color, #1e1e1e);
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.5), 0 2px 8px rgba(0, 0, 0, 0.3);
  }
  .markdown-editor-backdrop {
    background-color: rgba(0, 0, 0, 0.7);
  }
  .lexical-toolbar {
    background-color: var(--card-background-color, #1e1e1e);
    box-shadow: 0 2px 4px rgba(0, 0, 0, 0.3);
  }
  .toolbar-btn {
    color: var(--color, #c9d1d9);
  }
  .toolbar-btn:hover {
    background-color: rgba(255, 255, 255, 0.1);
    border-color: rgba(255, 255, 255, 0.1);
  }
  .toolbar-btn:active {
    background-color: var(--primary);
    border-color: var(--primary);
  }
  .toolbar-divider {
    background-color: rgba(255, 255, 255, 0.15);
  }
  .toolbar-select {
    background-color: transparent;
    border-color: rgba(255, 255, 255, 0.2);
    color: var(--color, #c9d1d9);
  }
  .toolbar-select:hover,
  .toolbar-select:focus {
    border-color: var(--primary, #58a6ff);
  }
  #lexical-editor-root {
    color: var(--color, #c9d1d9);
    background-color: var(--card-background-color, #1e1e1e);
  }
  #lexical-editor-root :deep(blockquote) {
    border-left-color: rgba(255, 255, 255, 0.2);
    color: #8b949e;
  }
  #lexical-editor-root :deep(code) {
    background-color: rgba(110, 118, 129, 0.4);
    border-color: rgba(255, 255, 255, 0.1);
    color: #c9d1d9;
  }
  #lexical-editor-root :deep(.lexical-code) {
    background-color: #0d1117;
    border-color: rgba(255, 255, 255, 0.1);
    color: #c9d1d9;
  }
  #lexical-editor-root :deep(.lexical-code .tokenComment) { color: #8b949e; }
  #lexical-editor-root :deep(.lexical-code .tokenPunctuation) { color: #c9d1d9; }
  #lexical-editor-root :deep(.lexical-code .tokenProperty) { color: #79c0ff; }
  #lexical-editor-root :deep(.lexical-code .tokenSelector) { color: #a5d6ff; }
  #lexical-editor-root :deep(.lexical-code .tokenOperator) { color: #79c0ff; }
  #lexical-editor-root :deep(.lexical-code .tokenAttr) { color: #ff7b72; }
  #lexical-editor-root :deep(.lexical-code .tokenVariable) { color: #ffa657; }
  #lexical-editor-root :deep(.lexical-code .tokenFunction) { color: #d2a8ff; }
  #lexical-editor-root :deep(.lexical-link),
  #lexical-editor-root :deep(a) {
    color: #58a6ff;
  }
}
</style>
