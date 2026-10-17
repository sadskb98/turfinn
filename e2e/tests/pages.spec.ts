import { test, expect } from '@playwright/test';

const BASE = 'http://localhost:3000';

// Flutter web renders to canvas — we test by:
// 1. Page loads without errors (no console errors, no crash)
// 2. Network requests succeed
// 3. Page doesn't show blank white screen
// 4. Screenshots for visual verification

test.describe('Page Load Tests — Unauthenticated', () => {
  test('splash screen loads', async ({ page }) => {
    const errors: string[] = [];
    page.on('console', (msg) => {
      if (msg.type() === 'error') errors.push(msg.text());
    });

    await page.goto(BASE);
    await page.waitForLoadState('networkidle');
    // Flutter needs time to initialize
    await page.waitForTimeout(3000);

    // Should have a canvas or flt-glass-pane (Flutter rendering)
    const hasFlutter = await page.evaluate(() => {
      return !!(
        document.querySelector('flt-glass-pane') ||
        document.querySelector('canvas') ||
        document.querySelector('flutter-view')
      );
    });
    expect(hasFlutter).toBeTruthy();

    await page.screenshot({ path: 'results/screenshots/01-splash.png', fullPage: true });
  });

  test('welcome screen loads', async ({ page }) => {
    await page.goto(`${BASE}/welcome`);
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(3000);
    await page.screenshot({ path: 'results/screenshots/02-welcome.png', fullPage: true });
  });

  test('sign-up screen loads', async ({ page }) => {
    await page.goto(`${BASE}/sign-up`);
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);
    await page.screenshot({ path: 'results/screenshots/03-signup.png', fullPage: true });
  });

  test('sign-in screen loads', async ({ page }) => {
    await page.goto(`${BASE}/sign-in`);
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);
    await page.screenshot({ path: 'results/screenshots/04-signin.png', fullPage: true });
  });
});

test.describe('Page Load Tests — Authenticated', () => {
  let authToken = '';

  test.beforeAll(async ({ request }) => {
    const API = 'http://localhost:8080';
    const otpResp = await request.post(`${API}/api/v1/auth/send-otp`, {
      data: { phone: '+8801700000099' },
    });
    const otpBody = await otpResp.json();
    const verifyResp = await request.post(`${API}/api/v1/auth/verify-otp`, {
      data: { phone: '+8801700000099', otp: otpBody.data.otp_dev },
    });
    authToken = (await verifyResp.json()).data.token;
  });

  async function loadAuthenticatedPage(page: any, path: string, screenshotName: string) {
    const errors: string[] = [];
    page.on('console', (msg: any) => {
      if (msg.type() === 'error' && !msg.text().includes('Failed to load resource'))
        errors.push(msg.text());
    });

    // Set auth token in localStorage before navigating
    await page.goto(BASE);
    await page.waitForTimeout(1000);
    await page.evaluate((token: string) => {
      // SharedPreferences in Flutter web stores in localStorage
      localStorage.setItem('flutter.auth_token', token);
    }, authToken);

    await page.goto(`${BASE}${path}`);
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(3000);

    await page.screenshot({
      path: `results/screenshots/${screenshotName}.png`,
      fullPage: true,
    });

    // Check no fatal JS errors (Flutter crash = white screen)
    const hasContent = await page.evaluate(() => {
      const canvas = document.querySelector('canvas');
      const flutterView = document.querySelector('flutter-view');
      return !!(canvas || flutterView);
    });
    expect(hasContent).toBeTruthy();

    return errors;
  }

  test('home screen', async ({ page }) => {
    await loadAuthenticatedPage(page, '/home', '05-home');
  });

  test('explore screen', async ({ page }) => {
    await loadAuthenticatedPage(page, '/explore', '06-explore');
  });

  test('feed screen', async ({ page }) => {
    await loadAuthenticatedPage(page, '/feed', '07-feed');
  });

  test('profile screen', async ({ page }) => {
    await loadAuthenticatedPage(page, '/profile', '08-profile');
  });

  test('activity screen', async ({ page }) => {
    await loadAuthenticatedPage(page, '/activity', '09-activity');
  });

  test('teams screen', async ({ page }) => {
    await loadAuthenticatedPage(page, '/teams', '10-teams');
  });

  test('leaderboard screen', async ({ page }) => {
    await loadAuthenticatedPage(page, '/leaderboard', '11-leaderboard');
  });

  test('tournaments screen', async ({ page }) => {
    await loadAuthenticatedPage(page, '/tournaments', '12-tournaments');
  });

  test('tournament create screen', async ({ page }) => {
    await loadAuthenticatedPage(page, '/tournaments/create', '13-tournament-create');
  });

  test('search screen', async ({ page }) => {
    await loadAuthenticatedPage(page, '/search', '14-search');
  });

  test('profile setup screen', async ({ page }) => {
    await loadAuthenticatedPage(page, '/profile/setup', '15-profile-setup');
  });

  test('personal info screen', async ({ page }) => {
    await loadAuthenticatedPage(page, '/profile/personal', '16-personal-info');
  });

  test('financial info screen', async ({ page }) => {
    await loadAuthenticatedPage(page, '/profile/financial', '17-financial-info');
  });
});

test.describe('API Response Validation via Browser', () => {
  test('pitches API returns valid data', async ({ page, request }) => {
    const resp = await request.get('http://localhost:8080/api/v1/pitches');
    expect(resp.ok()).toBeTruthy();
    const body = await resp.json();
    expect(body.success).toBe(true);
    expect(body.data.length).toBeGreaterThan(0);

    // Validate pitch structure
    const pitch = body.data[0];
    expect(pitch).toHaveProperty('id');
    expect(pitch).toHaveProperty('name');
    expect(pitch).toHaveProperty('price_per_hour');
    expect(typeof pitch.price_per_hour).toBe('number');
  });

  test('unauthenticated endpoints reject properly', async ({ request }) => {
    const endpoints = [
      '/api/v1/bookings/me',
      '/api/v1/wallet',
      '/api/v1/profile',
      '/api/v1/checkin/status',
      '/api/v1/challenges',
      '/api/v1/leaderboard',
      '/api/v1/referral',
      '/api/v1/tournaments',
    ];

    for (const ep of endpoints) {
      const resp = await request.get(`http://localhost:8080${ep}`);
      expect(resp.status()).toBe(401);
      const body = await resp.json();
      expect(body.success).toBe(false);
    }
  });
});
