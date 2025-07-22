<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <title>🧱 Welcome to Helix</title>
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <link rel="stylesheet" href="resources/styles.css" />
</head>
<body class="dark">

  <div class="welcome-container">

    <!-- Helix Header -->
    <div class="welcome-header">
      <svg width="64" height="64" viewBox="0 0 64 64" fill="none">
        <circle cx="32" cy="32" r="30" stroke="#00d9ff" stroke-width="4"/>
        <path d="M20 44 C30 34, 34 30, 44 20" stroke="#00d9ff" stroke-width="4" fill="none"/>
        <path d="M20 20 C30 30, 34 34, 44 44" stroke="#00d9ff" stroke-width="4" fill="none"/>
      </svg>
      <h1>🧱 Welcome to Helix</h1>
      <p>Your advanced identity and access management platform.</p>
    </div>

    <!-- Welcome Content -->
    <div class="welcome-content">
      <div class="feature-grid">
        <div class="feature-card">
          <h3>🔐 Secure Authentication</h3>
          <p>Enterprise-grade security with modern authentication protocols.</p>
        </div>
        <div class="feature-card">
          <h3>👥 User Management</h3>
          <p>Comprehensive user lifecycle management and access control.</p>
        </div>
        <div class="feature-card">
          <h3>🌐 Single Sign-On</h3>
          <p>Seamless access across all your applications and services.</p>
        </div>
        <div class="feature-card">
          <h3>🛡️ Advanced Security</h3>
          <p>Multi-factor authentication and advanced threat protection.</p>
        </div>
      </div>
    </div>

    <!-- Navigation -->
    <div class="welcome-nav">
      <a href="${url.loginUrl}" class="btn-primary">🚪 Admin Console</a>
      <a href="${url.accountUrl}" class="btn-secondary">👤 Account Portal</a>
    </div>

    <!-- Footer -->
    <div class="welcome-footer">
      <p>&copy; 2025 Helix Identity Platform. All rights reserved.</p>
      <p>Powered by Keycloak ${product.version}</p>
    </div>
  </div>

  <!-- Theme Toggle Button -->
  <div class="theme-toggle">
    <button id="toggle-theme" aria-label="Toggle Dark/Light Mode">🌗 Toggle Theme</button>
  </div>

  <!-- Theme Script -->
  <script>
    const toggleButton = document.getElementById('toggle-theme');
    const prefersDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;

    function setTheme(theme) {
      document.body.classList.remove('dark', 'light');
      document.body.classList.add(theme);
      localStorage.setItem('theme', theme);
    }

    // Load saved or system theme
    const stored = localStorage.getItem('theme');
    if (stored === 'light' || stored === 'dark') {
      setTheme(stored);
    } else {
      setTheme(prefersDark ? 'dark' : 'light');
    }

    toggleButton.addEventListener('click', () => {
      const isDark = document.body.classList.contains('dark');
      setTheme(isDark ? 'light' : 'dark');
    });
  </script>

</body>
</html>
