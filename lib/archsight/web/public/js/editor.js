// Editor JavaScript - Form handling, relation management, and markdown editor

// Import Lexical editor module (only when needed)
let lexicalModule = null;
let lexicalInitialized = false;
let currentTextareaId = null;

// Lazy load Lexical module
async function loadLexicalModule() {
  if (!lexicalModule) {
    lexicalModule = await import('./lexical-editor.js');
  }
  return lexicalModule;
}

// Open the markdown editor overlay
async function openMarkdownEditor(textareaId) {
  const overlay = document.getElementById('markdown-editor-overlay');
  const textarea = document.getElementById(textareaId);

  if (!overlay || !textarea) return;

  currentTextareaId = textareaId;

  // Load Lexical module if not already loaded
  const { initLexicalEditor, setLexicalMarkdown } = await loadLexicalModule();

  // Initialize Lexical if not already done
  if (!lexicalInitialized) {
    const editorRoot = document.getElementById('lexical-editor-root');
    if (editorRoot) {
      initLexicalEditor(editorRoot);
      lexicalInitialized = true;
    }
  }

  // Load content from textarea
  setLexicalMarkdown(textarea.value);

  // Show overlay
  overlay.classList.remove('hidden');
  document.body.style.overflow = 'hidden';
}

// Save content from Lexical editor back to textarea
async function saveMarkdownEditor() {
  const textarea = document.getElementById(currentTextareaId);

  if (textarea && lexicalModule) {
    const markdown = await lexicalModule.getLexicalMarkdown();
    textarea.value = markdown;
  }

  closeMarkdownEditor();
}

// Close the markdown editor overlay
function closeMarkdownEditor() {
  const overlay = document.getElementById('markdown-editor-overlay');
  if (overlay) {
    overlay.classList.add('hidden');
  }
  document.body.style.overflow = '';
  currentTextareaId = null;
}

// Format text (bold, italic, etc.)
function formatLexical(format) {
  if (lexicalModule) {
    lexicalModule.formatText(format);
  }
}

// Format block (headings, lists, quotes)
function formatLexicalBlock(blockType) {
  if (lexicalModule) {
    lexicalModule.formatBlock(blockType);
  }
}

// Insert a code block
function insertCodeBlock() {
  if (lexicalModule) {
    lexicalModule.insertCodeBlock('');
    // Show language selector after inserting
    setTimeout(() => updateCodeLanguageSelector(), 50);
  }
}

// Apply language from the selector dropdown
function applyCodeLanguage(language) {
  if (lexicalModule && language) {
    lexicalModule.setCodeBlockLanguage(language);
  }
  hideCodeLanguageSelector();
}

// Show/hide the code language selector in toolbar
function updateCodeLanguageSelector() {
  const picker = document.getElementById('code-language-picker');
  if (!picker || !lexicalModule) return;

  const currentLang = lexicalModule.getCurrentCodeLanguage();

  if (currentLang !== null) {
    // We're in a code block - show selector and set current value
    picker.classList.remove('hidden');
    picker.value = currentLang || '';
  } else {
    picker.classList.add('hidden');
  }
}

function hideCodeLanguageSelector() {
  const picker = document.getElementById('code-language-picker');
  if (picker) {
    picker.classList.add('hidden');
  }
}

// Insert a link
function insertLink() {
  if (lexicalModule) {
    lexicalModule.insertLink();
  }
}


// Expose markdown editor functions to global scope for onclick handlers
window.openMarkdownEditor = openMarkdownEditor;
window.saveMarkdownEditor = saveMarkdownEditor;
window.closeMarkdownEditor = closeMarkdownEditor;
window.formatLexical = formatLexical;
window.formatLexicalBlock = formatLexicalBlock;
window.insertCodeBlock = insertCodeBlock;
window.applyCodeLanguage = applyCodeLanguage;
window.insertLink = insertLink;

// Add a new relation from the inline form
function addRelation() {
  const verbKindSelect = document.getElementById('new-relation-verb-kind');
  const instanceSelect = document.getElementById('new-relation-instance');

  if (!verbKindSelect || !instanceSelect) return;

  const verbKind = verbKindSelect.value;
  const instance = instanceSelect.value;

  // Validate all fields are selected
  if (!verbKind || !instance) return;

  // Parse verb:kind format
  const [verb, kind] = verbKind.split(':', 2);
  if (!verb || !kind) return;

  // Create relation item with hidden inputs
  const item = document.createElement('div');
  item.className = 'relation-item';
  item.innerHTML = `
    <span class="relation-text">
      <strong>${escapeHtml(verb)}</strong> &rarr; ${escapeHtml(kind)}: <em>${escapeHtml(instance)}</em>
    </span>
    <input type="hidden" name="relations[][verb]" value="${escapeHtml(verb)}">
    <input type="hidden" name="relations[][kind]" value="${escapeHtml(kind)}">
    <input type="hidden" name="relations[][name]" value="${escapeHtml(instance)}">
    <button class="btn-remove" type="button" onclick="removeRelation(this)" title="Remove">
      <i class="iconoir-xmark"></i>
    </button>
  `;

  // Add to list
  const relationsList = document.getElementById('relations-list');
  if (relationsList) {
    relationsList.appendChild(item);
    sortRelations();
  }

  // Clear the form
  clearAddForm();
}

// Remove a relation from the list
function removeRelation(button) {
  const item = button.closest('.relation-item');
  if (item) {
    item.remove();
  }
}

// Sort relations alphabetically by verb, kind, instance
function sortRelations() {
  const relationsList = document.getElementById('relations-list');
  if (!relationsList) return;

  const items = Array.from(relationsList.querySelectorAll('.relation-item'));
  if (items.length === 0) return;

  items.sort((a, b) => {
    const getValues = (el) => {
      const verb = el.querySelector('input[name="relations[][verb]"]')?.value || '';
      const kind = el.querySelector('input[name="relations[][kind]"]')?.value || '';
      const name = el.querySelector('input[name="relations[][name]"]')?.value || '';
      return [verb, kind, name];
    };

    const [aVerb, aKind, aName] = getValues(a);
    const [bVerb, bKind, bName] = getValues(b);

    return aVerb.localeCompare(bVerb) ||
           aKind.localeCompare(bKind) ||
           aName.localeCompare(bName);
  });

  // Re-append in sorted order
  items.forEach(item => relationsList.appendChild(item));
}

// Clear the add relation form
function clearAddForm() {
  const verbKindSelect = document.getElementById('new-relation-verb-kind');
  const instanceSelect = document.getElementById('new-relation-instance');

  if (verbKindSelect) verbKindSelect.value = '';
  if (instanceSelect) {
    instanceSelect.innerHTML = '<option value="">Select instance...</option>';
  }
}

// Update instance dropdown based on selected verb:kind
// Uses embedded data instead of HTMX API calls
function updateInstanceOptions() {
  const verbKindSelect = document.getElementById('new-relation-verb-kind');
  const instanceSelect = document.getElementById('new-relation-instance');
  const editor = document.querySelector('.relations-editor');

  if (!verbKindSelect || !instanceSelect || !editor) return;

  // Clear and reset
  instanceSelect.innerHTML = '<option value="">Select instance...</option>';

  const verbKind = verbKindSelect.value;
  if (!verbKind) return;

  // Parse kind from verb:kind
  const parts = verbKind.split(':');
  if (parts.length < 2) return;
  const kind = parts.slice(1).join(':'); // Handle kinds that might contain colons

  // Get instances from embedded data
  const instancesData = JSON.parse(editor.dataset.instances || '{}');
  const instances = instancesData[kind] || [];

  // Populate dropdown
  instances.forEach(name => {
    const option = document.createElement('option');
    option.value = name;
    option.textContent = name;
    instanceSelect.appendChild(option);
  });
}

// Escape HTML to prevent XSS
function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

// Expose relation functions to global scope for onclick handlers
window.addRelation = addRelation;
window.removeRelation = removeRelation;
window.updateInstanceOptions = updateInstanceOptions;

// Copy YAML to clipboard
document.addEventListener('DOMContentLoaded', function() {
  const copyButton = document.getElementById('copy-yaml');
  if (copyButton) {
    copyButton.addEventListener('click', function() {
      const yamlContent = document.getElementById('yaml-content');
      if (!yamlContent) return;

      const yaml = yamlContent.textContent;

      navigator.clipboard.writeText(yaml).then(function() {
        // Show success feedback
        const originalText = copyButton.innerHTML;
        copyButton.innerHTML = '<i class="iconoir-check"></i> Copied!';
        copyButton.classList.add('copied');

        setTimeout(function() {
          copyButton.innerHTML = originalText;
          copyButton.classList.remove('copied');
        }, 2000);
      }).catch(function(err) {
        console.error('Failed to copy YAML:', err);
        // Fallback for older browsers
        const textarea = document.createElement('textarea');
        textarea.value = yaml;
        textarea.style.position = 'fixed';
        textarea.style.opacity = '0';
        document.body.appendChild(textarea);
        textarea.select();
        document.execCommand('copy');
        document.body.removeChild(textarea);

        const originalText = copyButton.innerHTML;
        copyButton.innerHTML = '<i class="iconoir-check"></i> Copied!';
        copyButton.classList.add('copied');

        setTimeout(function() {
          copyButton.innerHTML = originalText;
          copyButton.classList.remove('copied');
        }, 2000);
      });
    });
  }

  // Save YAML to source file (inline edit)
  const saveButton = document.getElementById('save-yaml');
  if (saveButton) {
    saveButton.addEventListener('click', async function() {
      const yamlContent = document.getElementById('yaml-content');
      if (!yamlContent) return;

      const yaml = yamlContent.textContent;
      const kind = this.dataset.kind;
      const name = this.dataset.name;
      const originalText = this.innerHTML;

      this.disabled = true;
      this.innerHTML = '<i class="iconoir-refresh"></i> Saving...';

      try {
        const response = await fetch(`/api/v1/editor/kinds/${kind}/instances/${name}/save`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ yaml: yaml })
        });

        const result = await response.json();
        if (result.success) {
          this.innerHTML = '<i class="iconoir-check"></i> Saved!';
          this.classList.add('saved');
          setTimeout(() => {
            this.innerHTML = originalText;
            this.classList.remove('saved');
            this.disabled = false;
          }, 2000);
        } else {
          alert('Save failed: ' + result.error);
          this.innerHTML = originalText;
          this.disabled = false;
        }
      } catch (err) {
        alert('Save failed: ' + err.message);
        this.innerHTML = originalText;
        this.disabled = false;
      }
    });
  }

  // Close overlay when pressing Escape
  document.addEventListener('keydown', function(event) {
    if (event.key === 'Escape') {
      const overlay = document.getElementById('markdown-editor-overlay');
      if (overlay && !overlay.classList.contains('hidden')) {
        closeMarkdownEditor();
      }
    }
  });

  // Track clicks in editor to show/hide code language selector
  const editorRoot = document.getElementById('lexical-editor-root');
  if (editorRoot) {
    editorRoot.addEventListener('click', function(event) {
      // Delay to let Lexical update selection
      setTimeout(() => {
        if (lexicalModule) {
          updateCodeLanguageSelector();
        }
      }, 10);
    });

    // Also track selection changes
    document.addEventListener('selectionchange', function() {
      if (lexicalModule && !document.querySelector('#markdown-editor-overlay.hidden')) {
        updateCodeLanguageSelector();
      }
    });
  }
});
