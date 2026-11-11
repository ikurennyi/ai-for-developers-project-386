import { createRouter, createWebHistory } from 'vue-router'
import TechnicalView from '../views/TechnicalView.vue'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [{ path: '/', name: 'technical', component: TechnicalView }],
})

export default router
