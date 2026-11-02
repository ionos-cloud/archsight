<script setup>
import { ref } from 'vue'

// The finished slide deck of a page (a PDF, or one self-contained HTML page made by any slide tool). Archsight does not
// render slides: the file is shown in a frame next to the page's summary. An HTML deck is somebody else's script, so its
// frame is sandboxed without same-origin (the server sends the same policy). A deck with a cover starts as a poster that
// loads the deck on click, one without starts right away.
const props = defineProps({
  slides: Object, // { url, filename, type: 'pdf' | 'html', cover_url }
})

const frameBox = ref(null)
const open = ref(!props.slides.cover_url)

function fullscreen() {
  open.value = true
  requestAnimationFrame(() => frameBox.value?.requestFullscreen?.())
}
</script>

<template>
  <section class="slides-block" aria-label="Slide deck">
    <div ref="frameBox" :class="['slides-frame', `slides-${slides.type}`]">
      <iframe
        v-if="open"
        :src="slides.type === 'pdf' ? `${slides.url}#view=FitH` : slides.url"
        :title="`Slides: ${slides.filename}`"
        :sandbox="slides.type === 'html' ? 'allow-scripts allow-popups' : undefined"
        allow="fullscreen"
        loading="lazy"
      ></iframe>
      <button v-else type="button" class="slides-poster" aria-label="Show the slides" title="Show the slides" @click="open = true">
        <img v-if="slides.cover_url" :src="slides.cover_url" alt="" />
        <span class="slides-play" aria-hidden="true"><i class="iconoir-play-solid"></i></span>
      </button>
    </div>
    <div class="slides-actions">
      <button type="button" class="btn-header" title="Show the slides full screen" @click="fullscreen">
        <i class="iconoir-expand"></i> Full screen
      </button>
      <a class="btn-header" :href="slides.url" target="_blank" rel="noopener" title="Open the slides in their own tab">
        <i class="iconoir-open-new-window"></i> Open
      </a>
      <a class="btn-header" :href="slides.url" :download="slides.filename" title="Download the slides">
        <i class="iconoir-download"></i> Download {{ slides.type.toUpperCase() }}
      </a>
    </div>
  </section>
</template>
