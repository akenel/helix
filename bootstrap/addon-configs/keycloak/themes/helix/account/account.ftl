<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <title>🧱 Helix Account Portal</title>
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <link rel="stylesheet" href="resources/styles.css" />
</head>
<body class="dark">

  <div class="account-container">

    <!-- Helix Header -->
    <div class="account-header">
      <svg width="48" height="48" viewBox="0 0 64 64" fill="none">
        <circle cx="32" cy="32" r="30" stroke="#00d9ff" stroke-width="4"/>
        <path d="M20 44 C30 34, 34 30, 44 20" stroke="#00d9ff" stroke-width="4" fill="none"/>
        <path d="M20 20 C30 30, 34 34, 44 44" stroke="#00d9ff" stroke-width="4" fill="none"/>
      </svg>
      <h2>🧱 Welcome to Helix</h2>
      <p>Your personalized identity dashboard.</p>
    </div>

    <!-- Account Info -->
    <div class="account-summary">
      <p><strong>Username:</strong> ${account.username}</p>
      <p><strong>Email:</strong> ${account.email}</p>
      <#if account.createdTimestamp??>
        <p><strong>Created:</strong> ${account.createdTimestamp?datetime}</p>
      </#if>
    </div>

    <!-- Navigation -->
    <div class="account-nav">
      <p>
        <a href="${url.accountUrl}">🔙 Return to Dashboard</a> |
        <a href="${url.logoutUrl}">🚪 Logout</a>
      </p>
    </div>

    <!-- Footer -->
    <div class="account-footer">
      <p>&copy; 2025 Helix Identity. All rights reserved.</p>
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
