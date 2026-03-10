<script setup>
import { computed } from 'vue'
import { httpGit } from '../../composables/useFormatting.js'

const props = defineProps({ annotations: Object })
const gitUrl = computed(() => props.annotations['repository/git'])
const httpUrl = computed(() => gitUrl.value ? httpGit(gitUrl.value) : null)

function copyClone() {
  navigator.clipboard.writeText(`git clone ${gitUrl.value}`)
}
</script>

<template>
  <tr v-if="gitUrl">
    <th scope="row">
      <a class="git-link" :href="httpUrl" target="_blank">Git Repo</a>
    </th>
    <td>
      <div class="git-info">
        <div class="git-item">
          <i class="iconoir-git-branch"></i>
          <code class="git-clone-command">git clone {{ gitUrl }}</code>
        </div>
        <button class="copy-button" @click="copyClone" title="Copy to clipboard">
          <i class="iconoir-copy"></i>
        </button>
      </div>
    </td>
  </tr>
</template>

<style scoped>
.git-info {
  display: flex;
  flex-wrap: wrap;
  gap: 16px;
  padding: 4px 0;
}

.git-item {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 6px 12px;
  background-color: var(--card-background-color);
  border-radius: 6px;
  border: 1px solid var(--muted-border-color);
}

.git-item i {
  font-size: 1.2em;
  color: var(--primary);
}

.git-link {
  font-weight: 600;
  color: var(--primary);
  text-decoration: none;
}

.git-link:hover {
  text-decoration: underline;
}

.git-clone-command {
  color: var(--muted-color);
  font-size: 0.9em;
  font-family: monospace;
  background-color: var(--code-background-color);
  padding: 2px 6px;
  border-radius: 3px;
}

.copy-button {
  padding: 6px;
  background-color: transparent;
  color: var(--primary);
  border: 1px solid var(--muted-border-color);
  border-radius: 4px;
  cursor: pointer;
  transition: all 0.2s ease;
  display: flex;
  align-items: center;
  justify-content: center;
  min-width: 32px;
  height: 32px;
}

.copy-button:hover {
  background-color: var(--card-background-color);
  border-color: var(--primary);
  transform: scale(1.1);
}

.copy-button.copied {
  background-color: #10b981;
  border-color: #10b981;
  color: white;
}

.copy-button i {
  font-size: 1.1em;
}
</style>
