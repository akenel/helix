<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <title>🧱 Helix Login</title>
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <link rel="stylesheet" href="resources/styles.css" />
</head>
<body class="dark">

  <div class="login-container">
    <div class="login-box">

      <!-- Logo -->
      <div class="helix-logo">
        <svg width="48" height="48" viewBox="0 0 64 64" fill="none">
          <circle cx="32" cy="32" r="30" stroke="#00d9ff" stroke-width="4"/>
          <path d="M20 44 C30 34, 34 30, 44 20" stroke="#00d9ff" stroke-width="4" fill="none"/>
          <path d="M20 20 C30 30, 34 34, 44 44" stroke="#00d9ff" stroke-width="4" fill="none"/>
        </svg>
      </div>

      <h1>🧱 Welcome to Helix</h1>

      <!-- Message -->
      <#if message?has_content>
        <div class="alert ${message.type}">
          ${message.summary}
        </div>
      </#if>

      <!-- Login Form -->
      <form id="kc-form-login" action="${url.loginAction}" method="post">
        <div class="form-group">
          <label for="username">Username</label>
          <input tabindex="1" id="username" name="username" type="text" autofocus />
        </div>
        <div class="form-group">
          <label for="password">Password</label>
          <input tabindex="2" id="password" name="password" type="password" />
        </div>
        <input tabindex="3" type="submit" value="Login" />
      </form>

      <!-- Links -->
      <div class="links">
        <#if realm.registrationAllowed?? && realm.registrationAllowed>
          <a href="${url.registrationUrl}">📝 Register</a>
        </#if>
        <#if realm.resetPasswordAllowed?? && realm.resetPasswordAllowed>
          <a href="${url.loginResetCredentialsUrl}">🔑 Forgot Password?</a>
        </#if>
      </div>

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
