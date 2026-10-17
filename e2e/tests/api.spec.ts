import { test, expect } from '@playwright/test';

const API = 'http://localhost:8080';
let authToken = '';
let userId = '';

test.describe('API Health & Auth', () => {
  test('health check', async ({ request }) => {
    const resp = await request.get(`${API}/health`);
    expect(resp.ok()).toBeTruthy();
    const body = await resp.json();
    expect(body.status).toBe('ok');
  });

  test('send OTP', async ({ request }) => {
    const resp = await request.post(`${API}/api/v1/auth/send-otp`, {
      data: { phone: '+8801700000001' },
    });
    expect(resp.ok()).toBeTruthy();
    const body = await resp.json();
    expect(body.success).toBe(true);
    // In dev mode, OTP is returned in response
    expect(body.data).toHaveProperty('otp_dev');
  });

  test('verify OTP and get token', async ({ request }) => {
    // Send OTP first
    const otpResp = await request.post(`${API}/api/v1/auth/send-otp`, {
      data: { phone: '+8801700000001' },
    });
    const otpBody = await otpResp.json();
    const otp = otpBody.data.otp_dev;

    // Verify OTP
    const resp = await request.post(`${API}/api/v1/auth/verify-otp`, {
      data: { phone: '+8801700000001', otp },
    });
    expect(resp.ok()).toBeTruthy();
    const body = await resp.json();
    expect(body.success).toBe(true);
    expect(body.data).toHaveProperty('token');
    authToken = body.data.token;
    userId = body.data.user?.id || '';
  });
});

test.describe('Authenticated API Endpoints', () => {
  test.beforeAll(async ({ request }) => {
    const otpResp = await request.post(`${API}/api/v1/auth/send-otp`, {
      data: { phone: '+8801700000001' },
    });
    const otpBody = await otpResp.json();
    const verifyResp = await request.post(`${API}/api/v1/auth/verify-otp`, {
      data: { phone: '+8801700000001', otp: otpBody.data.otp_dev },
    });
    const verifyBody = await verifyResp.json();
    authToken = verifyBody.data.token;
  });

  const authed = (path: string) => ({
    url: `${API}${path}`,
    headers: { Authorization: `Bearer ${authToken}` },
  });

  test('GET /users/me', async ({ request }) => {
    const { url, headers } = authed('/api/v1/users/me');
    const resp = await request.get(url, { headers });
    expect(resp.ok()).toBeTruthy();
    const body = await resp.json();
    expect(body.data).toHaveProperty('id');
    expect(body.data).toHaveProperty('phone', '+8801700000001');
  });

  test('GET /profile', async ({ request }) => {
    const { url, headers } = authed('/api/v1/profile');
    const resp = await request.get(url, { headers });
    expect(resp.ok()).toBeTruthy();
    const body = await resp.json();
    expect(body.data).toHaveProperty('coins_balance');
    expect(body.data).toHaveProperty('badges');
    expect(body.data).toHaveProperty('xp');
    expect(body.data).toHaveProperty('level');
    expect(body.data).toHaveProperty('level_title');
    expect(body.data).toHaveProperty('current_streak');
    expect(body.data).toHaveProperty('referral_code');
  });

  test('GET /wallet', async ({ request }) => {
    const { url, headers } = authed('/api/v1/wallet');
    const resp = await request.get(url, { headers });
    expect(resp.ok()).toBeTruthy();
    const body = await resp.json();
    expect(body.data).toHaveProperty('balance');
    expect(typeof body.data.balance).toBe('number');
  });

  test('GET /pitches', async ({ request }) => {
    const resp = await request.get(`${API}/api/v1/pitches`);
    expect(resp.ok()).toBeTruthy();
    const body = await resp.json();
    expect(body.data).toBeInstanceOf(Array);
    expect(body.data.length).toBeGreaterThan(0);
  });

  test('GET /pitches/:id/slots', async ({ request }) => {
    // Get first pitch
    const pitchResp = await request.get(`${API}/api/v1/pitches`);
    const pitches = (await pitchResp.json()).data;
    if (pitches.length === 0) return;

    const today = new Date().toISOString().split('T')[0];
    const resp = await request.get(
      `${API}/api/v1/pitches/${pitches[0].id}/slots?date=${today}`
    );
    expect(resp.ok()).toBeTruthy();
  });

  test('GET /bookings/me', async ({ request }) => {
    const { url, headers } = authed('/api/v1/bookings/me');
    const resp = await request.get(url, { headers });
    expect(resp.ok()).toBeTruthy();
    const body = await resp.json();
    expect(body.data).toBeInstanceOf(Array);
  });

  test('GET /checkin/status', async ({ request }) => {
    const { url, headers } = authed('/api/v1/checkin/status');
    const resp = await request.get(url, { headers });
    expect(resp.ok()).toBeTruthy();
    const body = await resp.json();
    expect(body.data).toHaveProperty('checked_in_today');
    expect(body.data).toHaveProperty('cycle');
    expect(body.data.cycle).toBeInstanceOf(Array);
  });

  test('POST /checkin', async ({ request }) => {
    const { url, headers } = authed('/api/v1/checkin');
    const resp = await request.post(url, { headers });
    // May fail if already checked in today — both are valid
    const body = await resp.json();
    if (resp.ok()) {
      expect(body.data).toHaveProperty('day');
      expect(body.data).toHaveProperty('coins_earned');
    } else {
      expect(body.error).toContain('already checked in');
    }
  });

  test('GET /challenges', async ({ request }) => {
    const { url, headers } = authed('/api/v1/challenges');
    const resp = await request.get(url, { headers });
    expect(resp.ok()).toBeTruthy();
    const body = await resp.json();
    expect(body.data).toBeInstanceOf(Array);
  });

  test('GET /leaderboard', async ({ request }) => {
    const { url, headers } = authed('/api/v1/leaderboard');
    const resp = await request.get(url, { headers });
    expect(resp.ok()).toBeTruthy();
    const body = await resp.json();
    expect(body.data).toHaveProperty('tier');
    expect(body.data).toHaveProperty('top');
  });

  test('GET /referral', async ({ request }) => {
    const { url, headers } = authed('/api/v1/referral');
    const resp = await request.get(url, { headers });
    expect(resp.ok()).toBeTruthy();
    const body = await resp.json();
    expect(body.data).toHaveProperty('code');
    expect(body.data.code.length).toBe(6);
  });

  test('GET /feed', async ({ request }) => {
    const { url, headers } = authed('/api/v1/feed');
    const resp = await request.get(url, { headers });
    expect(resp.ok()).toBeTruthy();
    const body = await resp.json();
    expect(body.data).toBeInstanceOf(Array);
  });

  test('GET /tournaments', async ({ request }) => {
    const { url, headers } = authed('/api/v1/tournaments');
    const resp = await request.get(url, { headers });
    expect(resp.ok()).toBeTruthy();
    const body = await resp.json();
    expect(body.data).toBeInstanceOf(Array);
  });

  test('GET /wallet/transactions', async ({ request }) => {
    const { url, headers } = authed('/api/v1/wallet/transactions');
    const resp = await request.get(url, { headers });
    expect(resp.ok()).toBeTruthy();
    const body = await resp.json();
    expect(body.data).toBeInstanceOf(Array);
  });
});

test.describe('Booking Flow', () => {
  test.beforeAll(async ({ request }) => {
    const otpResp = await request.post(`${API}/api/v1/auth/send-otp`, {
      data: { phone: '+8801700000001' },
    });
    const otpBody = await otpResp.json();
    const verifyResp = await request.post(`${API}/api/v1/auth/verify-otp`, {
      data: { phone: '+8801700000001', otp: otpBody.data.otp_dev },
    });
    authToken = (await verifyResp.json()).data.token;
  });

  test('create booking → conflicts check → cancel', async ({ request }) => {
    const headers = { Authorization: `Bearer ${authToken}` };

    // Get a pitch
    const pitchResp = await request.get(`${API}/api/v1/pitches`);
    const pitches = (await pitchResp.json()).data;
    expect(pitches.length).toBeGreaterThan(0);
    const pitchId = pitches[0].id;

    // Book tomorrow at 10am-11am
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    tomorrow.setHours(10, 0, 0, 0);
    const startsAt = tomorrow.toISOString();
    const endsAt = new Date(tomorrow.getTime() + 60 * 60 * 1000).toISOString();

    const bookResp = await request.post(`${API}/api/v1/bookings`, {
      headers,
      data: { pitch_id: pitchId, starts_at: startsAt, ends_at: endsAt },
    });
    expect(bookResp.ok()).toBeTruthy();
    const booking = (await bookResp.json()).data;
    expect(booking).toHaveProperty('id');

    // Try same slot — should conflict
    const conflictResp = await request.post(`${API}/api/v1/bookings`, {
      headers,
      data: { pitch_id: pitchId, starts_at: startsAt, ends_at: endsAt },
    });
    expect(conflictResp.ok()).toBeFalsy();

    // Cancel booking
    const cancelResp = await request.delete(`${API}/api/v1/bookings/${booking.id}`, { headers });
    expect(cancelResp.ok()).toBeTruthy();
  });
});

test.describe('Team & Tournament Flow', () => {
  let token2 = '';

  test.beforeAll(async ({ request }) => {
    // Create two users
    const otp1 = await request.post(`${API}/api/v1/auth/send-otp`, { data: { phone: '+8801700000002' } });
    const otp1Body = await otp1.json();
    const v1 = await request.post(`${API}/api/v1/auth/verify-otp`, {
      data: { phone: '+8801700000002', otp: otp1Body.data.otp_dev },
    });
    authToken = (await v1.json()).data.token;

    const otp2 = await request.post(`${API}/api/v1/auth/send-otp`, { data: { phone: '+8801700000003' } });
    const otp2Body = await otp2.json();
    const v2 = await request.post(`${API}/api/v1/auth/verify-otp`, {
      data: { phone: '+8801700000003', otp: otp2Body.data.otp_dev },
    });
    token2 = (await v2.json()).data.token;
  });

  test('create team', async ({ request }) => {
    const resp = await request.post(`${API}/api/v1/teams`, {
      headers: { Authorization: `Bearer ${authToken}` },
      data: { name: 'Test FC', format: '5 vs 5', formation: '2-1-1' },
    });
    expect(resp.ok()).toBeTruthy();
    const body = await resp.json();
    expect(body.data).toHaveProperty('id');
    expect(body.data).toHaveProperty('code');
    expect(body.data.name).toBe('Test FC');
  });

  test('create tournament', async ({ request }) => {
    const resp = await request.post(`${API}/api/v1/tournaments`, {
      headers: { Authorization: `Bearer ${authToken}` },
      data: {
        name: 'E2E Test Cup',
        format: '5 vs 5',
        max_teams: 4,
        entry_fee: 0,
        min_coins: 0,
        visibility: 'public',
      },
    });
    expect(resp.ok()).toBeTruthy();
    const body = await resp.json();
    expect(body.data).toHaveProperty('id');
    expect(body.data.name).toBe('E2E Test Cup');
    expect(body.data.status).toBe('registration_open');
  });

  test('cancel tournament', async ({ request }) => {
    // Create
    const createResp = await request.post(`${API}/api/v1/tournaments`, {
      headers: { Authorization: `Bearer ${authToken}` },
      data: { name: 'Cancel Test', format: '5 vs 5', max_teams: 4 },
    });
    const tid = (await createResp.json()).data.id;

    // Cancel
    const cancelResp = await request.post(`${API}/api/v1/tournaments/${tid}/cancel`, {
      headers: { Authorization: `Bearer ${authToken}` },
    });
    expect(cancelResp.ok()).toBeTruthy();
  });
});
