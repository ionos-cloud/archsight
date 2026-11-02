<script setup>
import PageView from '../page/PageView.vue'
import { displayName } from '../../composables/useFormatting.js'
import RelationsGrid from './RelationsGrid.vue'
import PdfButton from '../common/PdfButton.vue'

// Detail view of a Page resource: the rendered page (properties, contents, body, backlinks) with
// the resource actions on top, instead of the generic annotation table.
defineProps({
  data: Object,
  kindMeta: Object,
})
</script>

<template>
  <PageView :name="data.name">
    <template #actions>
      <div class="page-actions">
        <span class="page-resource">
          <i v-if="kindMeta" :class="`iconoir-${kindMeta.icon} icon-${kindMeta.layer}`"></i>
          Page <code>{{ displayName(data.name, 'Page') }}</code>
        </span>
        <router-link class="btn-header" :to="{ name: 'page', params: { name: data.name } }" title="Open in the handbook tree">
          <i class="iconoir-book"></i> Open in handbook
        </router-link>
        <PdfButton :name="data.name" />
        <router-link class="btn-header" :to="`/kinds/Page/instances/${encodeURIComponent(data.name)}/edit`" title="Edit this page">
          <i class="iconoir-edit-pencil"></i> Edit
        </router-link>
      </div>
    </template>
  </PageView>

  <RelationsGrid :data="data" />
</template>
