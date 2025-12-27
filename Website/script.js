/* ============================================
   FIT33 WEBSITE SCRIPTS
   ============================================ */

// Navigation scroll effect
window.addEventListener('scroll', () => {
  const navbar = document.getElementById('navbar');
  if (window.scrollY > 50) {
    navbar.classList.add('scrolled');
  } else {
    navbar.classList.remove('scrolled');
  }
});

// Mobile navigation toggle
function toggleNav() {
  const navLinks = document.getElementById('navLinks');
  const navToggle = document.getElementById('navToggle');
  navLinks.classList.toggle('active');
  navToggle.classList.toggle('active');
}

// FAQ accordion toggle
function toggleFaq(element) {
  // Close other open items
  const allItems = document.querySelectorAll('.faq-item');
  allItems.forEach(item => {
    if (item !== element && item.classList.contains('active')) {
      item.classList.remove('active');
    }
  });
  
  // Toggle current item
  element.classList.toggle('active');
}

// Help center search (basic filter)
document.addEventListener('DOMContentLoaded', () => {
  const searchInput = document.getElementById('helpSearch');
  
  if (searchInput) {
    searchInput.addEventListener('input', (e) => {
      const query = e.target.value.toLowerCase();
      const faqItems = document.querySelectorAll('.faq-item');
      const categories = document.querySelectorAll('.help-category');
      
      // Filter FAQ items
      faqItems.forEach(item => {
        const question = item.querySelector('.faq-question').textContent.toLowerCase();
        const answer = item.querySelector('.faq-answer-content').textContent.toLowerCase();
        
        if (question.includes(query) || answer.includes(query) || query === '') {
          item.style.display = 'block';
        } else {
          item.style.display = 'none';
        }
      });
      
      // Filter categories
      categories.forEach(cat => {
        const title = cat.querySelector('h3').textContent.toLowerCase();
        const desc = cat.querySelector('p').textContent.toLowerCase();
        
        if (title.includes(query) || desc.includes(query) || query === '') {
          cat.style.display = 'block';
        } else {
          cat.style.display = 'none';
        }
      });
    });
  }
});

// Intersection Observer for animations
const observerOptions = {
  root: null,
  rootMargin: '0px',
  threshold: 0.1
};

const observer = new IntersectionObserver((entries) => {
  entries.forEach(entry => {
    if (entry.isIntersecting) {
      entry.target.style.animationPlayState = 'running';
      observer.unobserve(entry.target);
    }
  });
}, observerOptions);

// Observe all animated elements on page load
document.addEventListener('DOMContentLoaded', () => {
  const animatedElements = document.querySelectorAll('.animate-in');
  animatedElements.forEach(el => {
    el.style.animationPlayState = 'paused';
    observer.observe(el);
  });
});

// Smooth scroll for anchor links
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
  anchor.addEventListener('click', function (e) {
    e.preventDefault();
    const target = document.querySelector(this.getAttribute('href'));
    if (target) {
      target.scrollIntoView({
        behavior: 'smooth',
        block: 'start'
      });
    }
  });
});

// Close mobile nav when clicking outside
document.addEventListener('click', (e) => {
  const navLinks = document.getElementById('navLinks');
  const navToggle = document.getElementById('navToggle');
  
  if (navLinks && navLinks.classList.contains('active')) {
    if (!e.target.closest('.nav-links') && !e.target.closest('.nav-toggle')) {
      navLinks.classList.remove('active');
      if (navToggle) navToggle.classList.remove('active');
    }
  }
});

// Analytics helper (placeholder - integrate with your analytics)
function trackEvent(category, action, label) {
  console.log(`[Analytics] ${category} - ${action}: ${label}`);
  // Add your analytics tracking here (Google Analytics, Mixpanel, etc.)
}

// Track App Store clicks
document.querySelectorAll('a[href*="apps.apple.com"]').forEach(link => {
  link.addEventListener('click', () => {
    trackEvent('CTA', 'Click', 'App Store Download');
  });
});

// Track help article views
document.querySelectorAll('.help-category').forEach(cat => {
  cat.addEventListener('click', () => {
    const title = cat.querySelector('h3').textContent;
    trackEvent('Help Center', 'Category Click', title);
  });
});

