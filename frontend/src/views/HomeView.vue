<template>
  <div class="home-page">
    <header class="site-header">
      <a class="brand" href="/" aria-label="Calendar home">Calendar</a>
      <nav aria-label="Main navigation">
        <a class="nav-link" href="/book">Book</a>
        <a class="nav-link admin-link" href="/admin">Admin</a>
      </nav>
    </header>

    <main>
      <section class="hero" aria-labelledby="hero-title">
        <div class="hero-copy">
          <p class="eyebrow">Simple scheduling, more meaningful conversations</p>
          <h1 id="hero-title">Book a call in minutes</h1>
          <p class="hero-description">
            Book a meeting in a minute: choose an event type and a time that works for you.
          </p>
          <a class="primary-link" href="/book">Book now <span aria-hidden="true">→</span></a>
          <p class="no-account">No account needed</p>
        </div>
        <div class="hero-art" aria-hidden="true">
          <div class="calendar-card">
            <div class="calendar-card-heading">
              <span class="calendar-icon">C</span>
              <span>Find a time</span>
              <span class="calendar-dots">•••</span>
            </div>
            <div class="calendar-month"><span>November 2026</span><span>‹ &nbsp; ›</span></div>
            <div class="calendar-grid calendar-week">
              <span>Mo</span><span>Tu</span><span>We</span><span>Th</span><span>Fr</span
              ><span>Sa</span><span>Su</span>
            </div>
            <div class="calendar-grid calendar-days">
              <span class="muted">26</span><span class="muted">27</span><span class="muted">28</span
              ><span class="muted">29</span><span class="muted">30</span><span>31</span
              ><span>1</span> <span>2</span><span>3</span><span>4</span><span>5</span
              ><span class="selected">6</span><span>7</span><span>8</span>
            </div>
            <div class="time-option"><span>15 min meeting</span><strong>10:30 am</strong></div>
            <div class="time-option secondary-time">
              <span>30 min meeting</span><strong>11:00 am</strong>
            </div>
          </div>
          <span class="decor decor-one"></span>
          <span class="decor decor-two"></span>
        </div>
      </section>

      <section class="features" aria-labelledby="features-title">
        <div class="section-heading">
          <p class="eyebrow">Made to keep it simple</p>
          <h2 id="features-title">Features</h2>
        </div>
        <div class="feature-list">
          <article class="feature-card">
            <span class="feature-number">01</span>
            <h3>Choose an event type and a convenient time</h3>
            <p>Find a meeting length and time that fit your schedule.</p>
          </article>
          <article class="feature-card">
            <span class="feature-number">02</span>
            <h3>Book quickly</h3>
            <p>Pick an available slot and arrange your call in just a few steps.</p>
          </article>
          <article class="feature-card">
            <span class="feature-number">03</span>
            <h3>Manage meeting types</h3>
            <p>Keep meeting options and their durations organized.</p>
          </article>
        </div>
      </section>
    </main>

    <footer class="site-footer">
      <a class="brand" href="/">Calendar</a><span>Make time for a good conversation.</span>
    </footer>
  </div>
</template>

<style>
:root {
  font-family:
    Inter,
    ui-sans-serif,
    system-ui,
    -apple-system,
    BlinkMacSystemFont,
    'Segoe UI',
    sans-serif;
  color: #172523;
  background: #fbfaf7;
  font-synthesis: none;
  text-rendering: optimizeLegibility;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
  font-optical-sizing: auto;
}

* {
  box-sizing: border-box;
}
body {
  margin: 0;
  min-width: 320px;
}
a {
  color: inherit;
  text-decoration: none;
}
.home-page {
  overflow: hidden;
}
.site-header,
.site-footer {
  width: min(1160px, calc(100% - 64px));
  margin: 0 auto;
}
.site-header {
  height: 88px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  border-bottom: 1px solid #e9e8e2;
}
.brand {
  font-size: 21px;
  font-weight: 750;
  letter-spacing: -0.8px;
}
.site-header nav {
  display: flex;
  align-items: center;
  gap: 32px;
}
.nav-link {
  font-size: 14px;
  font-weight: 600;
  color: #53615e;
  transition: color 160ms ease;
}
.nav-link:hover {
  color: #0e766b;
}
.admin-link {
  padding: 10px 17px;
  border: 1px solid #d9e0db;
  border-radius: 9px;
  color: #172523;
}
.hero {
  width: min(1160px, calc(100% - 64px));
  min-height: 570px;
  margin: 0 auto;
  display: grid;
  grid-template-columns: 1fr 0.92fr;
  align-items: center;
  gap: 56px;
  padding: 64px 0 76px;
}
.hero-copy {
  max-width: 540px;
}
.eyebrow {
  margin: 0 0 18px;
  color: #218477;
  font-size: 12px;
  font-weight: 750;
  letter-spacing: 1.4px;
  text-transform: uppercase;
}
h1 {
  max-width: 520px;
  margin: 0;
  font-size: clamp(48px, 6vw, 76px);
  line-height: 1.02;
  letter-spacing: -4.5px;
  font-weight: 720;
}
.hero-description {
  max-width: 460px;
  margin: 25px 0 30px;
  color: #63716d;
  font-size: 18px;
  line-height: 1.7;
}
.primary-link {
  display: inline-flex;
  align-items: center;
  gap: 16px;
  padding: 15px 22px;
  border-radius: 9px;
  background: #176f64;
  color: white;
  font-size: 15px;
  font-weight: 700;
  box-shadow: 0 8px 18px #176f6426;
  transition:
    background 160ms ease,
    transform 160ms ease;
}
.primary-link:hover {
  background: #11594f;
  transform: translateY(-1px);
}
.primary-link span {
  font-size: 20px;
  line-height: 14px;
}
.no-account {
  margin: 15px 0 0;
  color: #7c8883;
  font-size: 12px;
}
.hero-art {
  position: relative;
  min-height: 420px;
  display: grid;
  place-items: center;
  background: radial-gradient(ellipse at center, #e4f0e9 0%, #edf2ea 48%, transparent 70%);
}
.calendar-card {
  position: relative;
  z-index: 1;
  width: min(360px, 90%);
  padding: 22px;
  border: 1px solid #e7e9e3;
  border-radius: 16px;
  background: #fff;
  box-shadow: 0 24px 65px #183c3017;
  transform: rotate(2deg);
}
.calendar-card-heading,
.calendar-month {
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.calendar-card-heading {
  justify-content: flex-start;
  gap: 10px;
  font-size: 13px;
  font-weight: 700;
}
.calendar-icon {
  width: 25px;
  height: 25px;
  display: grid;
  place-items: center;
  border-radius: 7px;
  background: #176f64;
  color: #fff;
  font-size: 12px;
}
.calendar-dots {
  margin-left: auto;
  color: #9ca8a2;
  letter-spacing: 2px;
}
.calendar-month {
  margin: 23px 0 13px;
  font-size: 12px;
  font-weight: 650;
}
.calendar-month span:last-child {
  color: #87938d;
  font-size: 18px;
}
.calendar-grid {
  display: grid;
  grid-template-columns: repeat(7, 1fr);
  text-align: center;
}
.calendar-week {
  color: #97a19b;
  font-size: 10px;
}
.calendar-days {
  margin-top: 8px;
  row-gap: 5px;
}
.calendar-days span {
  height: 30px;
  display: grid;
  place-items: center;
  border-radius: 7px;
  color: #4b5853;
  font-size: 11px;
}
.calendar-days .muted {
  color: #c2c9c4;
}
.calendar-days .selected {
  background: #176f64;
  color: #fff;
}
.time-option {
  display: flex;
  justify-content: space-between;
  margin-top: 16px;
  padding: 12px;
  border: 1px solid #d8e9e3;
  border-radius: 8px;
  color: #68756f;
  font-size: 11px;
}
.time-option strong {
  color: #176f64;
  font-size: 11px;
}
.secondary-time {
  margin-top: 8px;
  border-color: #eceee9;
}
.secondary-time strong {
  color: #68756f;
}
.decor {
  position: absolute;
  border-radius: 50%;
  background: #e8ba75;
}
.decor-one {
  width: 15px;
  height: 15px;
  top: 61px;
  right: 59px;
}
.decor-two {
  width: 9px;
  height: 9px;
  left: 45px;
  bottom: 71px;
  background: #5caca0;
}
.features {
  padding: 72px 0 84px;
  background: #f1f3ed;
}
.section-heading,
.feature-list {
  width: min(1160px, calc(100% - 64px));
  margin: 0 auto;
}
.section-heading {
  margin-bottom: 32px;
}
.section-heading .eyebrow {
  margin-bottom: 9px;
}
h2 {
  margin: 0;
  font-size: 35px;
  letter-spacing: -1.4px;
}
.feature-list {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 18px;
}
.feature-card {
  min-height: 190px;
  padding: 24px;
  border: 1px solid #e5e8e1;
  border-radius: 12px;
  background: #fbfaf7;
}
.feature-number {
  color: #278679;
  font-size: 11px;
  font-weight: 750;
  letter-spacing: 1px;
}
.feature-card h3 {
  max-width: 280px;
  margin: 18px 0 9px;
  font-size: 17px;
  line-height: 1.35;
  letter-spacing: -0.3px;
}
.feature-card p {
  margin: 0;
  color: #74807b;
  font-size: 13px;
  line-height: 1.6;
}
.site-footer {
  min-height: 84px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  color: #75817c;
  font-size: 12px;
}
.site-footer .brand {
  color: #172523;
  font-size: 16px;
}

@media (max-width: 760px) {
  .site-header,
  .site-footer,
  .hero,
  .section-heading,
  .feature-list {
    width: min(100% - 40px, 560px);
  }
  .site-header {
    height: 72px;
  }
  .site-header nav {
    gap: 18px;
  }
  .admin-link {
    padding: 8px 12px;
  }
  .hero {
    grid-template-columns: 1fr;
    gap: 20px;
    padding: 64px 0 52px;
  }
  h1 {
    max-width: 480px;
    font-size: clamp(47px, 12vw, 66px);
    letter-spacing: -3px;
  }
  .hero-description {
    font-size: 16px;
  }
  .hero-art {
    min-height: 350px;
  }
  .calendar-card {
    width: min(340px, 86%);
  }
  .features {
    padding: 55px 0 60px;
  }
  .feature-list {
    grid-template-columns: 1fr;
  }
  .feature-card {
    min-height: auto;
  }
  .feature-card h3 {
    margin-top: 12px;
  }
}

@media (prefers-reduced-motion: reduce) {
  *,
  *::before,
  *::after {
    scroll-behavior: auto !important;
    transition-duration: 0.01ms !important;
  }
}
</style>
