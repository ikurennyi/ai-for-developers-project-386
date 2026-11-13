import { createRouter, createWebHistory } from 'vue-router'
import HomeView from '../views/HomeView.vue'
import AdminLayout from '../views/AdminLayout.vue'
import AdminLoginView from '../views/AdminLoginView.vue'
import AdminPageView from '../views/AdminPageView.vue'
import AdminLinksView from '../views/AdminLinksView.vue'
import NewMeetingTypeView from '../views/NewMeetingTypeView.vue'
import { hasAdminSession } from '../admin/session'
import MeetingTypesView from '../views/MeetingTypesView.vue'
import CalendarView from '../views/CalendarView.vue'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    { path: '/', name: 'home', component: HomeView },
    { path: '/book', name: 'meeting-types', component: MeetingTypesView },
    { path: '/book/:slug', name: 'meeting-calendar', component: CalendarView },
    { path: '/book/:slug/details', name: 'meeting-form', component: CalendarView },
    { path: '/admin/login', name: 'admin-login', component: AdminLoginView },
    {
      path: '/admin',
      component: AdminLayout,
      meta: { administrator: true },
      children: [
        { path: '', name: 'admin-home', component: AdminPageView, props: { title: 'Home' } },
        { path: 'links', name: 'admin-links', component: AdminLinksView },
        { path: 'links/new', name: 'admin-new-meeting-type', component: NewMeetingTypeView },
        { path: 'links/:id/edit', name: 'admin-edit-meeting-type', component: NewMeetingTypeView },
        {
          path: 'bookings',
          name: 'admin-bookings',
          component: AdminPageView,
          props: { title: 'Bookings' },
        },
      ],
    },
  ],
})

router.beforeEach(async (to) => {
  if (!to.meta.administrator) return true
  try {
    if (await hasAdminSession()) return true
  } catch {
    // Fail closed on network failure; the login page offers an explicit retry.
  }
  return { name: 'admin-login', query: { returnTo: to.fullPath } }
})

export default router
