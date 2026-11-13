import { createRouter, createWebHistory } from 'vue-router'
import HomeView from '../views/HomeView.vue'
import MeetingTypesView from '../views/MeetingTypesView.vue'
import CalendarView from '../views/CalendarView.vue'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    { path: '/', name: 'home', component: HomeView },
    { path: '/book', name: 'meeting-types', component: MeetingTypesView },
    { path: '/book/:slug', name: 'meeting-calendar', component: CalendarView },
    { path: '/book/:slug/details', name: 'meeting-form', component: CalendarView },
  ],
})

export default router
