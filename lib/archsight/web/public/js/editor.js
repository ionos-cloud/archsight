// Editor JavaScript - Form handling and relation management

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
});

