// Lexical Rich Text Editor Module for Markdown editing
// Uses ESM imports from esm.sh CDN

import { createEditor, $getRoot, $getSelection, $isRangeSelection, FORMAT_TEXT_COMMAND, $createTextNode } from 'https://esm.sh/lexical@0.20.0';
import { registerRichText, HeadingNode, QuoteNode, $createHeadingNode, $createQuoteNode } from 'https://esm.sh/@lexical/rich-text@0.20.0';
import { registerHistory, createEmptyHistoryState } from 'https://esm.sh/@lexical/history@0.20.0';
import { $convertFromMarkdownString, $convertToMarkdownString, TRANSFORMERS } from 'https://esm.sh/@lexical/markdown@0.20.0';
import { ListNode, ListItemNode, registerList, INSERT_ORDERED_LIST_COMMAND, INSERT_UNORDERED_LIST_COMMAND, REMOVE_LIST_COMMAND } from 'https://esm.sh/@lexical/list@0.20.0';
import { CodeNode, CodeHighlightNode, registerCodeHighlighting, $createCodeNode, $isCodeNode, getCodeLanguages } from 'https://esm.sh/@lexical/code@0.20.0';
import { LinkNode, $createLinkNode, $isLinkNode } from 'https://esm.sh/@lexical/link@0.20.0';
import { $setBlocksType } from 'https://esm.sh/@lexical/selection@0.20.0';
import { $createParagraphNode } from 'https://esm.sh/lexical@0.20.0';

let lexicalEditor = null;

/**
 * Initialize the Lexical editor in the given container element
 * @param {HTMLElement} containerElement - The contenteditable element to use as editor root
 * @returns {LexicalEditor} The initialized editor instance
 */
export function initLexicalEditor(containerElement) {
  const config = {
    namespace: 'ArchsightMarkdownEditor',
    nodes: [HeadingNode, QuoteNode, ListNode, ListItemNode, CodeNode, CodeHighlightNode, LinkNode],
    onError: (error) => {
      console.error('Lexical Editor Error:', error);
    },
    theme: {
      paragraph: 'lexical-paragraph',
      heading: {
        h1: 'lexical-h1',
        h2: 'lexical-h2',
        h3: 'lexical-h3',
      },
      list: {
        ul: 'lexical-ul',
        ol: 'lexical-ol',
        listitem: 'lexical-li',
      },
      quote: 'lexical-quote',
      code: 'lexical-code',
      codeHighlight: {
        atrule: 'tokenAttr',
        attr: 'tokenAttr',
        boolean: 'tokenProperty',
        builtin: 'tokenSelector',
        cdata: 'tokenComment',
        char: 'tokenSelector',
        class: 'tokenFunction',
        'class-name': 'tokenFunction',
        comment: 'tokenComment',
        constant: 'tokenProperty',
        deleted: 'tokenProperty',
        doctype: 'tokenComment',
        entity: 'tokenOperator',
        function: 'tokenFunction',
        important: 'tokenVariable',
        inserted: 'tokenSelector',
        keyword: 'tokenAttr',
        namespace: 'tokenVariable',
        number: 'tokenProperty',
        operator: 'tokenOperator',
        prolog: 'tokenComment',
        property: 'tokenProperty',
        punctuation: 'tokenPunctuation',
        regex: 'tokenVariable',
        selector: 'tokenSelector',
        string: 'tokenSelector',
        symbol: 'tokenProperty',
        tag: 'tokenProperty',
        url: 'tokenOperator',
        variable: 'tokenVariable',
      },
      link: 'lexical-link',
      text: {
        bold: 'lexical-bold',
        italic: 'lexical-italic',
        underline: 'lexical-underline',
        strikethrough: 'lexical-strikethrough',
        code: 'lexical-text-code',
      },
    },
  };

  lexicalEditor = createEditor(config);
  lexicalEditor.setRootElement(containerElement);

  // Register plugins
  registerRichText(lexicalEditor);
  registerList(lexicalEditor);
  registerCodeHighlighting(lexicalEditor);
  registerHistory(lexicalEditor, createEmptyHistoryState(), 300);

  return lexicalEditor;
}

/**
 * Set the editor content from markdown string
 * @param {string} markdown - The markdown string to load
 */
export function setLexicalMarkdown(markdown) {
  if (!lexicalEditor) return;

  lexicalEditor.update(() => {
    // Clear existing content and convert markdown
    const root = $getRoot();
    root.clear();
    $convertFromMarkdownString(markdown || '', TRANSFORMERS);
  });
}

/**
 * Get the current editor content as markdown string
 * @returns {Promise<string>} The markdown string
 */
export function getLexicalMarkdown() {
  return new Promise((resolve) => {
    if (!lexicalEditor) {
      resolve('');
      return;
    }

    lexicalEditor.update(() => {
      const markdown = $convertToMarkdownString(TRANSFORMERS);
      resolve(markdown);
    });
  });
}

/**
 * Get the editor instance
 * @returns {LexicalEditor|null} The editor instance
 */
export function getEditor() {
  return lexicalEditor;
}

/**
 * Execute a text format command (bold, italic, etc.)
 * @param {string} format - The format type ('bold', 'italic', 'underline', 'strikethrough', 'code')
 */
export function formatText(format) {
  if (!lexicalEditor) return;
  lexicalEditor.dispatchCommand(FORMAT_TEXT_COMMAND, format);
}

/**
 * Format selected block as heading, list, quote, or paragraph
 * @param {string} blockType - The block type ('h1', 'h2', 'h3', 'bullet', 'number', 'quote', 'paragraph')
 */
export function formatBlock(blockType) {
  if (!lexicalEditor) return;

  if (blockType === 'bullet') {
    lexicalEditor.dispatchCommand(INSERT_UNORDERED_LIST_COMMAND, undefined);
    return;
  }

  if (blockType === 'number') {
    lexicalEditor.dispatchCommand(INSERT_ORDERED_LIST_COMMAND, undefined);
    return;
  }

  lexicalEditor.update(() => {
    const selection = $getSelection();
    if ($isRangeSelection(selection)) {
      if (blockType === 'h1' || blockType === 'h2' || blockType === 'h3') {
        $setBlocksType(selection, () => $createHeadingNode(blockType));
      } else if (blockType === 'quote') {
        $setBlocksType(selection, () => $createQuoteNode());
      } else if (blockType === 'paragraph') {
        $setBlocksType(selection, () => $createParagraphNode());
      }
    }
  });
}

/**
 * Focus the editor
 */
export function focusEditor() {
  if (!lexicalEditor) return;
  lexicalEditor.focus();
}

/**
 * Insert a code block at current selection
 * @param {string} language - The programming language for the code block
 */
export function insertCodeBlock(language = '') {
  if (!lexicalEditor) return;

  lexicalEditor.update(() => {
    const selection = $getSelection();
    if ($isRangeSelection(selection)) {
      const codeNode = $createCodeNode(language);
      selection.insertNodes([codeNode]);
      codeNode.select();
    }
  });
}


/**
 * Set the language for the currently selected code block
 * @param {string} language - The programming language
 * @returns {boolean} True if language was set, false otherwise
 */
export function setCodeBlockLanguage(language) {
  if (!lexicalEditor) return false;

  let success = false;
  lexicalEditor.update(() => {
    const selection = $getSelection();
    if ($isRangeSelection(selection)) {
      const nodes = selection.getNodes();
      for (const node of nodes) {
        const parent = node.getParent();
        if ($isCodeNode(parent)) {
          parent.setLanguage(language);
          success = true;
          break;
        }
        if ($isCodeNode(node)) {
          node.setLanguage(language);
          success = true;
          break;
        }
      }
    }
  });
  return success;
}

/**
 * Get the current code node's language if cursor is in a code block
 * @returns {string|null} The language or null if not in a code block
 */
export function getCurrentCodeLanguage() {
  if (!lexicalEditor) return null;

  let language = null;
  lexicalEditor.getEditorState().read(() => {
    const selection = $getSelection();
    if ($isRangeSelection(selection)) {
      const nodes = selection.getNodes();
      for (const node of nodes) {
        const parent = node.getParent();
        if ($isCodeNode(parent)) {
          language = parent.getLanguage();
          break;
        }
        if ($isCodeNode(node)) {
          language = node.getLanguage();
          break;
        }
      }
    }
  });
  return language;
}

/**
 * Insert or toggle a link
 * Prompts user for URL if creating a new link
 */
export function insertLink() {
  if (!lexicalEditor) return;

  const url = prompt('Enter URL:', 'https://');
  if (url === null) return; // User cancelled

  lexicalEditor.update(() => {
    const selection = $getSelection();
    if (!$isRangeSelection(selection)) return;

    if (url === '') {
      // Remove link - unwrap link nodes
      const nodes = selection.getNodes();
      nodes.forEach(node => {
        const parent = node.getParent();
        if ($isLinkNode(parent)) {
          const children = parent.getChildren();
          for (const child of children) {
            parent.insertBefore(child);
          }
          parent.remove();
        }
      });
    } else {
      // Create link by wrapping selected content
      const selectedText = selection.getTextContent();
      if (selectedText) {
        // Has selection - wrap it in a link
        const linkNode = $createLinkNode(url);
        selection.insertNodes([linkNode]);
        // Move selected text into link
        linkNode.append($createTextNode(selectedText));
      } else {
        // No selection - insert link with URL as text
        const linkNode = $createLinkNode(url);
        linkNode.append($createTextNode(url));
        selection.insertNodes([linkNode]);
      }
    }
  });
}

