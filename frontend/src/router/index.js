import { createRouter, createWebHistory } from 'vue-router'

const routes = [
  {
    path: '/',
    name: 'home',
    component: () => import('../components/instance/GraphView.vue'),
  },
  {
    path: '/kinds/:kind',
    name: 'kind',
    component: () => import('../components/instance/KindList.vue'),
    props: true,
  },
  {
    path: '/kinds/:kind/instances/:instance',
    name: 'instance',
    component: () => import('../components/instance/InstanceRouter.vue'),
    props: true,
  },
  {
    path: '/search',
    name: 'search',
    component: () => import('../components/instance/SearchResults.vue'),
  },
  {
    path: '/doc/:filename(.*)',
    name: 'doc',
    component: () => import('../components/layout/DocPage.vue'),
    props: true,
  },
  {
    path: '/kinds/:kind/new',
    name: 'editor-new',
    component: () => import('../components/editor/EditorPage.vue'),
    props: true,
  },
  {
    path: '/kinds/:kind/instances/:instance/edit',
    name: 'editor-edit',
    component: () => import('../components/editor/EditorPage.vue'),
    props: true,
  },
  {
    path: '/error',
    name: 'error',
    component: () => import('../components/layout/ErrorPage.vue'),
  },
  {
    path: '/docs/api',
    name: 'api-docs',
    component: () => import('../components/layout/ApiDocsPage.vue'),
    meta: { fullscreen: true },
  },
]

export default createRouter({
  history: createWebHistory('/'),
  routes,
})
