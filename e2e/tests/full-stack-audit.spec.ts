import { test, expect } from '@playwright/test';

const API = 'http://localhost:8080';

// Tokens for different roles
let playerToken = '';
let playerUserId = '';
let managerToken = '';
let managerUserId = '';
let adminToken = '';
let superAdminToken = '';

// Shared IDs
let pitchId = '';
let pitchId2 = '';
let bookingId = '';
let teamId = '';
let teamCode = '';
let tournamentId = '';
let feedPostId = '';
let managePitchId = '';

// Bug tracking
const bugs: {
  id: number;
  severity: string;
  endpoint: string;
  status: number;
  error: string;
  detail: string;
  app: string;
}[] = [];
let bugCounter = 0;

function reportBug(
  severity: 'CRITICAL' | 'HIGH' | 'MEDIUM' | 'LOW',
  app: 'Player' | 'Manager' | 'SuperAdmin' | 'API' | 'Cross-App',
  endpoint: string,
  status: number,
  error: string,
  detail: string,
) {
  bugCounter++;
  bugs.push({ id: bugCounter, severity, endpoint, status, error, detail, app });
  console.log(`BUG-${bugCounter} [${severity}][${app}]: ${endpoint} -> ${status} -- ${error}`);
}

async function getToken(request: any, phone: string): Promise<string> {
  const otpResp = await request.post(`${API}/api/v1/auth/send-otp`, {
    data: { phone },
  });
  const otpBody = await otpResp.json();
  if (!otpBody.data?.otp_dev) throw new Error(`OTP send failed for ${phone}: ${JSON.stringify(otpBody)}`);

  const verifyResp = await request.post(`${API}/api/v1/auth/verify-otp`, {
    data: { phone, otp: otpBody.data.otp_dev },
  });
  const verifyBody = await verifyResp.json();
  if (!verifyBody.data?.token) throw new Error(`OTP verify failed for ${phone}: ${JSON.stringify(verifyBody)}`);
  return verifyBody.data.token;
}

function authHeaders(token: string) {
  return { Authorization: `Bearer ${token}` };
}

// ═══════════════════════════════════════════════════════════════════════════════
// SETUP — Create users with different roles
// ═══════════════════════════════════════════════════════════════════════════════
test.describe.serial('Full Stack E2E Audit — Player + Manager + SuperAdmin', () => {

  test('SETUP: authenticate player user', async ({ request }) => {
    const phone = `+88017${Date.now().toString().slice(-8)}`;
    playerToken = await getToken(request, phone);
    expect(playerToken).toBeTruthy();

    // Get user ID
    const r = await request.get(`${API}/api/v1/users/me`, { headers: authHeaders(playerToken) });
    const b = await r.json();
    playerUserId = b.data.id;
  });

  test('SETUP: authenticate admin user (seeded)', async ({ request }) => {
    // Seeded admin phone from 002_seed.sql
    adminToken = await getToken(request, '+8801000000000');
    expect(adminToken).toBeTruthy();
  });

  test('SETUP: authenticate super_admin user (seeded)', async ({ request }) => {
    // Seeded super_admin phone from 020_fix_remaining_schema.sql
    superAdminToken = await getToken(request, '+8801000000001');
    expect(superAdminToken).toBeTruthy();
  });

  test('SETUP: create manager user and promote', async ({ request }) => {
    const phone = `+88018${Date.now().toString().slice(-8)}`;
    managerToken = await getToken(request, phone);
    expect(managerToken).toBeTruthy();

    // Get manager user ID
    const meResp = await request.get(`${API}/api/v1/users/me`, { headers: authHeaders(managerToken) });
    const meBody = await meResp.json();
    managerUserId = meBody.data.id;

    // Promote to manager via admin
    const promoteResp = await request.put(`${API}/api/v1/admin/users/${managerUserId}/role`, {
      headers: authHeaders(adminToken),
      data: { role: 'manager' },
    });
    if (!promoteResp.ok()) {
      const pb = await promoteResp.json();
      reportBug('CRITICAL', 'API', `PUT /admin/users/:id/role`, promoteResp.status(), pb.error || 'promote failed', 'Cannot promote user to manager — blocks all manager tests');
    }
    expect(promoteResp.ok()).toBeTruthy();

    // Re-authenticate to get JWT with updated role
    managerToken = await getToken(request, phone);
    expect(managerToken).toBeTruthy();
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION 1: HEALTH & PUBLIC ENDPOINTS
  // ═══════════════════════════════════════════════════════════════════════════
  test('1.1 GET /health', async ({ request }) => {
    const r = await request.get(`${API}/health`);
    expect(r.ok()).toBeTruthy();
    const b = await r.json();
    expect(b.status).toBe('ok');
  });

  test('1.2 GET /health — not rate limited', async ({ request }) => {
    // Hit health 10 times quickly — none should be 429
    for (let i = 0; i < 10; i++) {
      const r = await request.get(`${API}/health`);
      if (r.status() === 429) {
        reportBug('CRITICAL', 'API', 'GET /health', 429, 'health check rate limited', 'Docker health checks will fail under load');
        break;
      }
    }
  });

  test('1.3 GET /api/v1/config', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/config`);
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'API', 'GET /config', r.status(), b.error, '');
  });

  test('1.4 GET /api/v1/banners', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/banners`);
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'API', 'GET /banners', r.status(), b.error, '');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION 2: PLAYER APP — Auth, Profile, Wallet
  // ═══════════════════════════════════════════════════════════════════════════
  test('2.1 GET /users/me', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/users/me`, { headers: authHeaders(playerToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('HIGH', 'Player', 'GET /users/me', r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
    expect(b.data).toHaveProperty('id');
    expect(b.data).toHaveProperty('role');
  });

  test('2.2 PUT /users/me — update profile', async ({ request }) => {
    const r = await request.put(`${API}/api/v1/users/me`, {
      headers: authHeaders(playerToken),
      data: { name: 'E2E Player', position: 'Striker', skill_level: 'Advanced' },
    });
    const b = await r.json();
    if (!r.ok()) reportBug('HIGH', 'Player', 'PUT /users/me', r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
  });

  test('2.3 GET /profile — full gamification profile', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/profile`, { headers: authHeaders(playerToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('HIGH', 'Player', 'GET /profile', r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();

    const expectedFields = ['xp', 'level', 'level_title', 'xp_to_next_level', 'coins_balance', 'current_streak', 'referral_code', 'badges', 'total_bookings', 'name'];
    for (const field of expectedFields) {
      if (!(field in b.data)) {
        reportBug('HIGH', 'Player', 'GET /profile', 200, `missing field: ${field}`, `Present fields: ${Object.keys(b.data).join(', ')}`);
      }
    }
  });

  test('2.4 GET /wallet — balance', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/wallet`, { headers: authHeaders(playerToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('CRITICAL', 'Player', 'GET /wallet', r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
    if (!('balance' in b.data)) {
      reportBug('HIGH', 'Player', 'GET /wallet', 200, 'missing balance field', JSON.stringify(b.data));
    }
  });

  test('2.5 POST /wallet/topup', async ({ request }) => {
    const r = await request.post(`${API}/api/v1/wallet/topup`, {
      headers: authHeaders(playerToken),
      data: { amount: 500 },
    });
    const b = await r.json();
    if (!r.ok()) reportBug('CRITICAL', 'Player', 'POST /wallet/topup', r.status(), b.error, 'Wallet topup broken — likely wallet_transactions schema issue');
  });

  test('2.6 GET /wallet/transactions', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/wallet/transactions`, { headers: authHeaders(playerToken) });
    const b = await r.json();
    if (!r.ok()) {
      reportBug('CRITICAL', 'Player', 'GET /wallet/transactions', r.status(), b.error, 'wallet_transactions table schema mismatch — entity expects wallet_id/amount/type/reference, DB may have user_id/amount_paisa/description/ref_id');
    }
    // If topup worked, we should see at least one transaction
    if (r.ok() && b.data) {
      if (Array.isArray(b.data) && b.data.length > 0) {
        const tx = b.data[0];
        for (const field of ['id', 'amount', 'type', 'created_at']) {
          if (!(field in tx)) {
            reportBug('HIGH', 'Player', 'GET /wallet/transactions', 200, `transaction missing field: ${field}`, JSON.stringify(Object.keys(tx)));
          }
        }
      }
    }
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION 3: PLAYER APP — Gamification
  // ═══════════════════════════════════════════════════════════════════════════
  test('3.1 GET /checkin/status', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/checkin/status`, { headers: authHeaders(playerToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'Player', 'GET /checkin/status', r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
  });

  test('3.2 POST /checkin', async ({ request }) => {
    const r = await request.post(`${API}/api/v1/checkin`, { headers: authHeaders(playerToken) });
    const b = await r.json();
    if (!r.ok() && !b.error?.includes('already checked in')) {
      reportBug('MEDIUM', 'Player', 'POST /checkin', r.status(), b.error, '');
    }
  });

  test('3.3 GET /challenges', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/challenges`, { headers: authHeaders(playerToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'Player', 'GET /challenges', r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
  });

  test('3.4 GET /leaderboard', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/leaderboard`, { headers: authHeaders(playerToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'Player', 'GET /leaderboard', r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
  });

  test('3.5 GET /leaderboard/previous', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/leaderboard/previous`, { headers: authHeaders(playerToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'Player', 'GET /leaderboard/previous', r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
  });

  test('3.6 GET /referral', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/referral`, { headers: authHeaders(playerToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'Player', 'GET /referral', r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
    if (r.ok() && !b.data?.code) {
      reportBug('MEDIUM', 'Player', 'GET /referral', 200, 'missing referral code', JSON.stringify(b.data));
    }
  });

  test('3.7 POST /store/streak-freeze — should fail for 0-coin user', async ({ request }) => {
    const r = await request.post(`${API}/api/v1/store/streak-freeze`, { headers: authHeaders(playerToken) });
    // Expected to fail (insufficient coins or no streak)
    if (r.ok()) {
      reportBug('MEDIUM', 'Player', 'POST /store/streak-freeze', 200, 'unexpected success for new user', 'should require sufficient coins');
    }
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION 4: PLAYER APP — Pitches & Bookings
  // ═══════════════════════════════════════════════════════════════════════════
  test('4.1 GET /pitches — list all', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/pitches`);
    const b = await r.json();
    if (!r.ok()) reportBug('CRITICAL', 'Player', 'GET /pitches', r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
    expect(b.data.length).toBeGreaterThan(0);
    pitchId = b.data[0].id;
    if (b.data.length > 1) pitchId2 = b.data[1].id;
  });

  test('4.2 GET /pitches/:id', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/pitches/${pitchId}`);
    const b = await r.json();
    if (!r.ok()) reportBug('HIGH', 'Player', `GET /pitches/:id`, r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
    // Check expected fields
    for (const field of ['id', 'name', 'address', 'price_per_hour']) {
      if (!(field in b.data)) {
        reportBug('MEDIUM', 'Player', 'GET /pitches/:id', 200, `missing field: ${field}`, JSON.stringify(Object.keys(b.data)));
      }
    }
  });

  test('4.3 GET /pitches/:id/slots', async ({ request }) => {
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    const date = tomorrow.toISOString().split('T')[0];
    const r = await request.get(`${API}/api/v1/pitches/${pitchId}/slots?date=${date}`);
    const b = await r.json();
    if (!r.ok()) reportBug('HIGH', 'Player', 'GET /pitches/:id/slots', r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
  });

  test('4.4 POST /pitches/:id/reviews — create review', async ({ request }) => {
    const r = await request.post(`${API}/api/v1/pitches/${pitchId}/reviews`, {
      headers: authHeaders(playerToken),
      data: { rating: 4, comment: 'Great pitch, well maintained' },
    });
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'Player', 'POST /pitches/:id/reviews', r.status(), b.error, JSON.stringify(b));
  });

  test('4.5 GET /pitches/:id/reviews', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/pitches/${pitchId}/reviews`);
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'Player', 'GET /pitches/:id/reviews', r.status(), b.error, '');
  });

  test('4.6 POST /bookings — create booking', async ({ request }) => {
    const d = new Date();
    d.setDate(d.getDate() + 3);
    d.setHours(16, 0, 0, 0);
    const startsAt = d.toISOString();
    const endsAt = new Date(d.getTime() + 60 * 60 * 1000).toISOString();

    const r = await request.post(`${API}/api/v1/bookings`, {
      headers: authHeaders(playerToken),
      data: { pitch_id: pitchId, starts_at: startsAt, ends_at: endsAt },
    });
    const b = await r.json();
    if (!r.ok()) {
      reportBug('CRITICAL', 'Player', 'POST /bookings', r.status(), b.error, JSON.stringify(b));
    } else {
      bookingId = b.data.id;
      // Check pitch name is populated (BUG-7 fix)
      if (!b.data.pitch_name) {
        reportBug('HIGH', 'Player', 'POST /bookings', 201, 'pitch_name empty in create response', 'Pitch not preloaded after creation');
      }
    }
  });

  test('4.7 POST /bookings — duplicate slot conflict', async ({ request }) => {
    const d = new Date();
    d.setDate(d.getDate() + 3);
    d.setHours(16, 0, 0, 0);
    const startsAt = d.toISOString();
    const endsAt = new Date(d.getTime() + 60 * 60 * 1000).toISOString();

    const r = await request.post(`${API}/api/v1/bookings`, {
      headers: authHeaders(playerToken),
      data: { pitch_id: pitchId, starts_at: startsAt, ends_at: endsAt },
    });
    if (r.ok()) {
      reportBug('CRITICAL', 'Player', 'POST /bookings (duplicate)', 201, 'double-booking allowed', 'Conflict detection failed — same pitch+time accepted twice');
    }
  });

  test('4.8 GET /bookings/me', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/bookings/me`, { headers: authHeaders(playerToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('HIGH', 'Player', 'GET /bookings/me', r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
    if (Array.isArray(b.data) && b.data.length > 0) {
      const bk = b.data[0];
      if (!bk.pitch_name) {
        reportBug('HIGH', 'Player', 'GET /bookings/me', 200, 'pitch_name empty in list', 'Pitch not preloaded in ListByUser');
      }
    }
  });

  test('4.9 DELETE /bookings/:id — cancel booking', async ({ request }) => {
    if (!bookingId) return;
    const r = await request.delete(`${API}/api/v1/bookings/${bookingId}`, { headers: authHeaders(playerToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('HIGH', 'Player', 'DELETE /bookings/:id', r.status(), b.error, '');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION 5: PLAYER APP — Feed
  // ═══════════════════════════════════════════════════════════════════════════
  test('5.1 POST /feed — create match post', async ({ request }) => {
    const d = new Date();
    d.setDate(d.getDate() + 2);
    d.setHours(19, 0, 0, 0);
    const r = await request.post(`${API}/api/v1/feed`, {
      headers: authHeaders(playerToken),
      data: {
        pitch_id: pitchId,
        title: 'E2E Friendly Match',
        description: 'Looking for skilled players!',
        match_date: d.toISOString(),
        spots_total: 10,
      },
    });
    const b = await r.json();
    if (!r.ok()) {
      reportBug('HIGH', 'Player', 'POST /feed', r.status(), b.error, JSON.stringify(b));
    } else {
      feedPostId = b.data?.id;
    }
  });

  test('5.2 GET /feed', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/feed`, { headers: authHeaders(playerToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('HIGH', 'Player', 'GET /feed', r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
    // Check response structure
    if (r.ok() && Array.isArray(b.data) && b.data.length > 0) {
      const post = b.data[0];
      for (const field of ['id', 'title', 'spots_total', 'spots_filled']) {
        if (!(field in post)) {
          reportBug('MEDIUM', 'Player', 'GET /feed', 200, `feed post missing field: ${field}`, JSON.stringify(Object.keys(post)));
        }
      }
    }
  });

  test('5.3 POST /feed/:id/join — join own post should handle gracefully', async ({ request }) => {
    if (!feedPostId) return;
    const r = await request.post(`${API}/api/v1/feed/${feedPostId}/join`, {
      headers: authHeaders(playerToken),
    });
    // Joining own post — might succeed or reject gracefully
    const b = await r.json();
    if (r.status() === 500) {
      reportBug('HIGH', 'Player', 'POST /feed/:id/join', 500, b.error || 'internal error', 'Server error when joining feed post');
    }
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION 6: PLAYER APP — Teams
  // ═══════════════════════════════════════════════════════════════════════════
  test('6.1 POST /teams — create team', async ({ request }) => {
    const r = await request.post(`${API}/api/v1/teams`, {
      headers: authHeaders(playerToken),
      data: { name: `E2E Squad ${Date.now()}`, format: '5 vs 5', formation: '2-1-1' },
    });
    const b = await r.json();
    if (!r.ok()) {
      reportBug('HIGH', 'Player', 'POST /teams', r.status(), b.error, JSON.stringify(b));
    } else {
      teamId = b.data.id;
      teamCode = b.data.code;
    }
  });

  test('6.2 GET /teams/me — list my teams', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/teams/me`, { headers: authHeaders(playerToken) });
    const b = await r.json();
    if (!r.ok()) {
      reportBug('CRITICAL', 'Player', 'GET /teams/me', r.status(), b.error, 'Route may be matching /:id instead of /me — route ordering issue');
    } else {
      expect(Array.isArray(b.data)).toBeTruthy();
    }
  });

  test('6.3 GET /teams/:id', async ({ request }) => {
    if (!teamId) return;
    const r = await request.get(`${API}/api/v1/teams/${teamId}`, { headers: authHeaders(playerToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('HIGH', 'Player', 'GET /teams/:id', r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
  });

  test('6.4 PUT /teams/:id/formation', async ({ request }) => {
    if (!teamId) return;
    const r = await request.put(`${API}/api/v1/teams/${teamId}/formation`, {
      headers: authHeaders(playerToken),
      data: { formation: '2-2-1' },
    });
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'Player', 'PUT /teams/:id/formation', r.status(), b.error, '');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION 7: PLAYER APP — Tournaments
  // ═══════════════════════════════════════════════════════════════════════════
  test('7.1 POST /tournaments — create', async ({ request }) => {
    const r = await request.post(`${API}/api/v1/tournaments`, {
      headers: authHeaders(playerToken),
      data: {
        name: `E2E Cup ${Date.now()}`,
        format: '5v5',
        max_teams: 4,
        entry_fee: 0,
        min_coins: 0,
        visibility: 'public',
      },
    });
    const b = await r.json();
    if (!r.ok()) {
      reportBug('HIGH', 'Player', 'POST /tournaments', r.status(), b.error, JSON.stringify(b));
    } else {
      tournamentId = b.data.id;
    }
  });

  test('7.2 GET /tournaments', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/tournaments`, { headers: authHeaders(playerToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('HIGH', 'Player', 'GET /tournaments', r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
  });

  test('7.3 GET /tournaments/:id', async ({ request }) => {
    if (!tournamentId) return;
    const r = await request.get(`${API}/api/v1/tournaments/${tournamentId}`, { headers: authHeaders(playerToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('HIGH', 'Player', 'GET /tournaments/:id', r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
    if (b.data) {
      if (b.data.matches && !Array.isArray(b.data.matches)) {
        reportBug('MEDIUM', 'Player', 'GET /tournaments/:id', 200, 'matches is not array', typeof b.data.matches);
      }
      if (b.data.teams && !Array.isArray(b.data.teams)) {
        reportBug('MEDIUM', 'Player', 'GET /tournaments/:id', 200, 'teams is not array', typeof b.data.teams);
      }
    }
  });

  test('7.4 POST /tournaments/:id/join — join with team (format normalization)', async ({ request }) => {
    if (!tournamentId || !teamId) return;
    // Team format is "5 vs 5", tournament format is "5v5" — should still work after BUG-11 fix
    const r = await request.post(`${API}/api/v1/tournaments/${tournamentId}/join`, {
      headers: authHeaders(playerToken),
      data: { team_id: teamId },
    });
    const b = await r.json();
    if (!r.ok()) {
      reportBug('HIGH', 'Player', 'POST /tournaments/:id/join', r.status(), b.error, `Team format: "5 vs 5", Tournament format: "5v5" — format normalization may have failed`);
    }
  });

  test('7.5 POST /tournaments/:id/start — should fail (only 1 team)', async ({ request }) => {
    if (!tournamentId) return;
    const r = await request.post(`${API}/api/v1/tournaments/${tournamentId}/start`, {
      headers: authHeaders(playerToken),
    });
    const b = await r.json();
    if (r.ok()) {
      reportBug('HIGH', 'Player', 'POST /tournaments/:id/start', 200, 'started with 1 team', 'should require >= 2 teams');
    }
    // Check that the error message is meaningful (BUG-17 fix)
    if (!r.ok() && b.error) {
      if (b.error === 'internal server error' || b.error === '') {
        reportBug('MEDIUM', 'Player', 'POST /tournaments/:id/start', r.status(), 'generic error message', `Got: "${b.error}" — should show real reason`);
      }
    }
  });

  test('7.6 POST /tournaments/:id/cancel', async ({ request }) => {
    if (!tournamentId) return;
    const r = await request.post(`${API}/api/v1/tournaments/${tournamentId}/cancel`, {
      headers: authHeaders(playerToken),
    });
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'Player', 'POST /tournaments/:id/cancel', r.status(), b.error, JSON.stringify(b));
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION 8: TURF MANAGER — Dashboard & Analytics
  // ═══════════════════════════════════════════════════════════════════════════
  test('8.1 GET /manage/dashboard', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/manage/dashboard`, { headers: authHeaders(managerToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('CRITICAL', 'Manager', 'GET /manage/dashboard', r.status(), b.error, 'Turf Manager dashboard broken');
    // Check dashboard fields
    if (r.ok() && b.data) {
      for (const field of ['total_pitches', 'total_bookings', 'total_revenue']) {
        if (!(field in b.data)) {
          reportBug('HIGH', 'Manager', 'GET /manage/dashboard', 200, `missing field: ${field}`, JSON.stringify(Object.keys(b.data)));
        }
      }
    }
  });

  test('8.2 GET /manager/analytics/summary', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/manager/analytics/summary`, { headers: authHeaders(managerToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('HIGH', 'Manager', 'GET /manager/analytics/summary', r.status(), b.error, '');
  });

  test('8.3 GET /manager/analytics/revenue-chart', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/manager/analytics/revenue-chart?period=week`, { headers: authHeaders(managerToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('HIGH', 'Manager', 'GET /manager/analytics/revenue-chart', r.status(), b.error, '');
  });

  test('8.4 GET /manager/analytics/pitch-breakdown', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/manager/analytics/pitch-breakdown`, { headers: authHeaders(managerToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('HIGH', 'Manager', 'GET /manager/analytics/pitch-breakdown', r.status(), b.error, '');
  });

  test('8.5 GET /manager/analytics/heatmap', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/manager/analytics/heatmap`, { headers: authHeaders(managerToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'Manager', 'GET /manager/analytics/heatmap', r.status(), b.error, '');
  });

  test('8.6 GET /manager/analytics/peak-hours', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/manager/analytics/peak-hours`, { headers: authHeaders(managerToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'Manager', 'GET /manager/analytics/peak-hours', r.status(), b.error, '');
  });

  test('8.7 GET /manager/analytics/customers', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/manager/analytics/customers`, { headers: authHeaders(managerToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'Manager', 'GET /manager/analytics/customers', r.status(), b.error, '');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION 9: TURF MANAGER — Pitches CRUD
  // ═══════════════════════════════════════════════════════════════════════════
  test('9.1 POST /manage/pitches — create pitch', async ({ request }) => {
    const r = await request.post(`${API}/api/v1/manage/pitches`, {
      headers: authHeaders(managerToken),
      data: {
        name: 'E2E Test Pitch',
        description: 'Test pitch created by E2E',
        address: '123 Test Road, Dhaka',
        city: 'Dhaka',
        price_per_hour: 2000,
        surface: 'artificial',
        capacity: 10,
        image_urls: '',
      },
    });
    const b = await r.json();
    if (!r.ok()) {
      reportBug('HIGH', 'Manager', 'POST /manage/pitches', r.status(), b.error, JSON.stringify(b));
    } else {
      managePitchId = b.data?.id;
    }
  });

  test('9.2 GET /manage/pitches — list my pitches', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/manage/pitches`, { headers: authHeaders(managerToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('HIGH', 'Manager', 'GET /manage/pitches', r.status(), b.error, '');
  });

  test('9.3 PUT /manage/pitches/:id — update pitch', async ({ request }) => {
    if (!managePitchId) return;
    const r = await request.put(`${API}/api/v1/manage/pitches/${managePitchId}`, {
      headers: authHeaders(managerToken),
      data: { name: 'E2E Test Pitch Updated', address: '123 Test Road, Dhaka', city: 'Dhaka', price_per_hour: 2500 },
    });
    const b = await r.json();
    if (!r.ok()) reportBug('HIGH', 'Manager', 'PUT /manage/pitches/:id', r.status(), b.error, '');
  });

  test('9.4 PUT /manage/pitches/:id/toggle — toggle pitch visibility', async ({ request }) => {
    if (!managePitchId) return;
    const r = await request.put(`${API}/api/v1/manage/pitches/${managePitchId}/toggle`, {
      headers: authHeaders(managerToken),
    });
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'Manager', 'PUT /manage/pitches/:id/toggle', r.status(), b.error, '');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION 10: TURF MANAGER — Bookings & Walk-ins
  // ═══════════════════════════════════════════════════════════════════════════
  test('10.1 GET /manager/bookings', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/manager/bookings`, { headers: authHeaders(managerToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('HIGH', 'Manager', 'GET /manager/bookings', r.status(), b.error, '');
  });

  test('10.2 POST /manager/bookings — create walk-in', async ({ request }) => {
    if (!managePitchId) return;
    const d = new Date();
    d.setDate(d.getDate() + 4);
    d.setHours(10, 0, 0, 0);
    const r = await request.post(`${API}/api/v1/manager/bookings`, {
      headers: authHeaders(managerToken),
      data: {
        pitch_id: managePitchId,
        customer_name: 'Walk-in Customer',
        starts_at: d.toISOString(),
        ends_at: new Date(d.getTime() + 60 * 60 * 1000).toISOString(),
        payment_method: 'cash',
        payment_amount: 2000,
      },
    });
    const b = await r.json();
    if (!r.ok()) reportBug('HIGH', 'Manager', 'POST /manager/bookings (walk-in)', r.status(), b.error, JSON.stringify(b));
  });

  test('10.3 GET /manage/bookings', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/manage/bookings`, { headers: authHeaders(managerToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('HIGH', 'Manager', 'GET /manage/bookings', r.status(), b.error, '');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION 11: TURF MANAGER — Financials
  // ═══════════════════════════════════════════════════════════════════════════
  test('11.1 GET /manager/financials', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/manager/financials`, { headers: authHeaders(managerToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('HIGH', 'Manager', 'GET /manager/financials', r.status(), b.error, '');
  });

  test('11.2 GET /manager/financials/ledger', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/manager/financials/ledger`, { headers: authHeaders(managerToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'Manager', 'GET /manager/financials/ledger', r.status(), b.error, '');
  });

  test('11.3 GET /manager/financials/pitch-pnl', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/manager/financials/pitch-pnl`, { headers: authHeaders(managerToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'Manager', 'GET /manager/financials/pitch-pnl', r.status(), b.error, '');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION 12: TURF MANAGER — Promo Codes
  // ═══════════════════════════════════════════════════════════════════════════
  test('12.1 GET /manager/promos', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/manager/promos`, { headers: authHeaders(managerToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'Manager', 'GET /manager/promos', r.status(), b.error, '');
  });

  test('12.2 POST /manager/promos — create promo', async ({ request }) => {
    const r = await request.post(`${API}/api/v1/manager/promos`, {
      headers: authHeaders(managerToken),
      data: {
        code: `E2E${Date.now().toString().slice(-6)}`,
        discount_type: 'percent',
        discount_value: 10,
        max_uses: 50,
        valid_from: new Date().toISOString().slice(0, 10),
        valid_to: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10),
      },
    });
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'Manager', 'POST /manager/promos', r.status(), b.error, JSON.stringify(b));
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION 13: ADMIN PANEL
  // ═══════════════════════════════════════════════════════════════════════════
  test('13.1 GET /admin/dashboard', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/admin/dashboard`, { headers: authHeaders(adminToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('HIGH', 'SuperAdmin', 'GET /admin/dashboard', r.status(), b.error, '');
  });

  test('13.2 GET /admin/users', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/admin/users`, { headers: authHeaders(adminToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('HIGH', 'SuperAdmin', 'GET /admin/users', r.status(), b.error, '');
    if (r.ok() && Array.isArray(b.data)) {
      expect(b.data.length).toBeGreaterThan(0);
    }
  });

  test('13.3 GET /admin/pitches', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/admin/pitches`, { headers: authHeaders(adminToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('HIGH', 'SuperAdmin', 'GET /admin/pitches', r.status(), b.error, '');
  });

  test('13.4 GET /admin/bookings', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/admin/bookings`, { headers: authHeaders(adminToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('HIGH', 'SuperAdmin', 'GET /admin/bookings', r.status(), b.error, '');
  });

  test('13.5 GET /admin/teams', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/admin/teams`, { headers: authHeaders(adminToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('HIGH', 'SuperAdmin', 'GET /admin/teams', r.status(), b.error, '');
  });

  test('13.6 GET /admin/matches', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/admin/matches`, { headers: authHeaders(adminToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('HIGH', 'SuperAdmin', 'GET /admin/matches', r.status(), b.error, '');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION 14: PLATFORM CONFIG (Admin)
  // ═══════════════════════════════════════════════════════════════════════════
  test('14.1 GET /admin/platform/settings', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/admin/platform/settings`, { headers: authHeaders(adminToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('HIGH', 'SuperAdmin', 'GET /admin/platform/settings', r.status(), b.error, '');
  });

  test('14.2 GET /admin/platform/pricing-rules', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/admin/platform/pricing-rules`, { headers: authHeaders(adminToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'SuperAdmin', 'GET /admin/platform/pricing-rules', r.status(), b.error, '');
  });

  test('14.3 GET /admin/platform/flags', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/admin/platform/flags`, { headers: authHeaders(adminToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'SuperAdmin', 'GET /admin/platform/flags', r.status(), b.error, '');
  });

  test('14.4 GET /admin/platform/templates', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/admin/platform/templates`, { headers: authHeaders(adminToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'SuperAdmin', 'GET /admin/platform/templates', r.status(), b.error, '');
  });

  test('14.5 GET /admin/platform/settings/audit', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/admin/platform/settings/audit`, { headers: authHeaders(adminToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'SuperAdmin', 'GET /admin/platform/settings/audit', r.status(), b.error, '');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION 15: MARKETING (Admin)
  // ═══════════════════════════════════════════════════════════════════════════
  test('15.1 GET /admin/marketing/promo-codes', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/admin/marketing/promo-codes`, { headers: authHeaders(adminToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'SuperAdmin', 'GET /admin/marketing/promo-codes', r.status(), b.error, '');
  });

  test('15.2 GET /admin/marketing/campaigns', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/admin/marketing/campaigns`, { headers: authHeaders(adminToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'SuperAdmin', 'GET /admin/marketing/campaigns', r.status(), b.error, '');
  });

  test('15.3 GET /admin/marketing/featured-pitches', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/admin/marketing/featured-pitches`, { headers: authHeaders(adminToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'SuperAdmin', 'GET /admin/marketing/featured-pitches', r.status(), b.error, '');
  });

  test('15.4 GET /admin/marketing/referral-stats', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/admin/marketing/referral-stats`, { headers: authHeaders(adminToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'SuperAdmin', 'GET /admin/marketing/referral-stats', r.status(), b.error, '');
  });

  test('15.5 GET /admin/marketing/banners', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/admin/marketing/banners`, { headers: authHeaders(adminToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'SuperAdmin', 'GET /admin/marketing/banners', r.status(), b.error, '');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION 16: DISPUTES & SUPPORT (Admin)
  // ═══════════════════════════════════════════════════════════════════════════
  test('16.1 GET /admin/disputes', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/admin/disputes`, { headers: authHeaders(adminToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'SuperAdmin', 'GET /admin/disputes', r.status(), b.error, '');
  });

  test('16.2 GET /admin/tickets', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/admin/tickets`, { headers: authHeaders(adminToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'SuperAdmin', 'GET /admin/tickets', r.status(), b.error, '');
  });

  test('16.3 GET /admin/reviews/flagged', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/admin/reviews/flagged`, { headers: authHeaders(adminToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'SuperAdmin', 'GET /admin/reviews/flagged', r.status(), b.error, '');
  });

  test('16.4 GET /admin/kyc', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/admin/kyc`, { headers: authHeaders(adminToken) });
    const b = await r.json();
    if (!r.ok()) reportBug('MEDIUM', 'SuperAdmin', 'GET /admin/kyc', r.status(), b.error, '');
  });

  test('16.5 GET /manage/kyc/me — returns none for new manager', async ({ request }) => {
    // The manager user was freshly created in SETUP, so no KYC record should exist yet.
    // The endpoint must return HTTP 200 with status "none" (not 404).
    const r = await request.get(`${API}/api/v1/manage/kyc/me`, { headers: authHeaders(managerToken) });
    const b = await r.json();
    if (!r.ok()) {
      reportBug('HIGH', 'Manager', 'GET /manage/kyc/me', r.status(), b.error ?? b.message, 'KYC status check broken for new manager');
    } else {
      const status = b.data?.status ?? b.status;
      if (status !== 'none') {
        reportBug('MEDIUM', 'Manager', 'GET /manage/kyc/me', r.status(), `unexpected status: ${status}`, 'Expected "none" for a manager with no KYC record');
      }
      expect(status).toBe('none');
    }
  });

  test('16.6 POST /manage/kyc — submit KYC application', async ({ request }) => {
    const payload = {
      business_name: 'E2E Test Turf Co.',
      nid_number: '1234567890123',
      nid_photo_front_url: 'https://storage.example.com/kyc/nid-front.jpg',
      nid_photo_back_url: 'https://storage.example.com/kyc/nid-back.jpg',
      selfie_url: 'https://storage.example.com/kyc/selfie.jpg',
      payout_account: '01700000001',
    };
    const r = await request.post(`${API}/api/v1/manage/kyc`, {
      headers: authHeaders(managerToken),
      data: payload,
    });
    const b = await r.json();
    if (!r.ok()) {
      reportBug('HIGH', 'Manager', 'POST /manage/kyc', r.status(), b.error ?? b.message, 'KYC submission broken');
    } else {
      const status = b.data?.status ?? b.status;
      expect(['submitted', 'draft']).toContain(status);
    }
  });

  test('16.7 GET /manage/kyc/me — reflects submitted status after POST', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/manage/kyc/me`, { headers: authHeaders(managerToken) });
    const b = await r.json();
    if (!r.ok()) {
      reportBug('HIGH', 'Manager', 'GET /manage/kyc/me (post-submit)', r.status(), b.error ?? b.message, 'KYC status check broken after submission');
    } else {
      const status = b.data?.status ?? b.status;
      if (!['submitted', 'under_review', 'approved'].includes(status)) {
        reportBug('HIGH', 'Manager', 'GET /manage/kyc/me (post-submit)', r.status(), `unexpected status: ${status}`, 'KYC record not persisted after POST /manage/kyc');
      }
    }
  });

  test('16.8 POST /manage/kyc — duplicate submission is rejected', async ({ request }) => {
    // Submitting again while status is "submitted" or "under_review" must return 400/409.
    const payload = {
      business_name: 'Duplicate Attempt',
      nid_number: '9999999999999',
      nid_photo_front_url: 'https://storage.example.com/kyc/nid-front2.jpg',
      nid_photo_back_url: 'https://storage.example.com/kyc/nid-back2.jpg',
      selfie_url: 'https://storage.example.com/kyc/selfie2.jpg',
      payout_account: '01700000002',
    };
    const r = await request.post(`${API}/api/v1/manage/kyc`, {
      headers: authHeaders(managerToken),
      data: payload,
    });
    if (r.ok()) {
      reportBug('HIGH', 'Manager', 'POST /manage/kyc (duplicate)', r.status(), 'duplicate submission accepted', 'Should reject resubmission when status is submitted/under_review');
    } else {
      expect([400, 409, 422]).toContain(r.status());
    }
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION 17: SUPER ADMIN — BI & Finance
  // ═══════════════════════════════════════════════════════════════════════════
  test('17.1 GET /super-admin/north-star (needs super_admin role)', async ({ request }) => {
    // Admin user from seed has role "admin" not "super_admin" — test role enforcement
    const r = await request.get(`${API}/api/v1/super-admin/north-star`, { headers: authHeaders(adminToken) });
    // Admin should NOT access super_admin routes — expect 403 (or 429 if rate limited)
    expect([403, 429]).toContain(r.status());
  });

  test('17.2 VERIFY: super_admin token is valid', async ({ request }) => {
    // superAdminToken was obtained in SETUP phase
    expect(superAdminToken).toBeTruthy();
    const r = await request.get(`${API}/api/v1/users/me`, { headers: authHeaders(superAdminToken) });
    const b = await r.json();
    expect(b.data?.role).toBe('super_admin');
  });

  test('17.3 GET /super-admin/north-star', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/super-admin/north-star`, { headers: authHeaders(superAdminToken) });
    const b = await r.json();
    if (r.status() === 403) {
      reportBug('MEDIUM', 'SuperAdmin', 'GET /super-admin/north-star', 403, 'access denied', 'Seeded admin cannot access super_admin routes — need super_admin role');
    } else if (r.status() === 500) {
      reportBug('HIGH', 'SuperAdmin', 'GET /super-admin/north-star', 500, b.error, 'BI endpoint crashes');
    }
  });

  test('17.4 GET /super-admin/cohort-retention', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/super-admin/cohort-retention`, { headers: authHeaders(superAdminToken) });
    const b = await r.json();
    if (r.status() === 500) reportBug('HIGH', 'SuperAdmin', 'GET /super-admin/cohort-retention', 500, b.error, '');
  });

  test('17.5 GET /super-admin/funnel', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/super-admin/funnel`, { headers: authHeaders(superAdminToken) });
    const b = await r.json();
    if (r.status() === 500) reportBug('HIGH', 'SuperAdmin', 'GET /super-admin/funnel', 500, b.error, '');
  });

  test('17.6 GET /super-admin/revenue', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/super-admin/revenue?period=month`, { headers: authHeaders(superAdminToken) });
    const b = await r.json();
    if (r.status() === 500) reportBug('HIGH', 'SuperAdmin', 'GET /super-admin/revenue', 500, b.error, '');
  });

  test('17.7 GET /super-admin/audit-log', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/super-admin/audit-log`, { headers: authHeaders(superAdminToken) });
    const b = await r.json();
    if (r.status() === 500) reportBug('HIGH', 'SuperAdmin', 'GET /super-admin/audit-log', 500, b.error, '');
  });

  test('17.8 GET /super-admin/ledger', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/super-admin/ledger`, { headers: authHeaders(superAdminToken) });
    const b = await r.json();
    if (r.status() === 500) reportBug('HIGH', 'SuperAdmin', 'GET /super-admin/ledger', 500, b.error, '');
  });

  test('17.9 GET /super-admin/trial-balance', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/super-admin/trial-balance`, { headers: authHeaders(superAdminToken) });
    const b = await r.json();
    if (r.status() === 500) reportBug('HIGH', 'SuperAdmin', 'GET /super-admin/trial-balance', 500, b.error, '');
  });

  test('17.10 GET /super-admin/income-statement', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/super-admin/income-statement`, { headers: authHeaders(superAdminToken) });
    const b = await r.json();
    if (r.status() === 500) reportBug('HIGH', 'SuperAdmin', 'GET /super-admin/income-statement', 500, b.error, '');
  });

  test('17.11 GET /super-admin/vat-report', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/super-admin/vat-report`, { headers: authHeaders(superAdminToken) });
    const b = await r.json();
    if (r.status() === 500) reportBug('HIGH', 'SuperAdmin', 'GET /super-admin/vat-report', 500, b.error, '');
  });

  test('17.12 GET /super-admin/fraud-flags', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/super-admin/fraud-flags`, { headers: authHeaders(superAdminToken) });
    const b = await r.json();
    if (r.status() === 500) reportBug('HIGH', 'SuperAdmin', 'GET /super-admin/fraud-flags', 500, b.error, '');
  });

  test('17.13 GET /super-admin/rate-limits', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/super-admin/rate-limits`, { headers: authHeaders(superAdminToken) });
    const b = await r.json();
    if (r.status() === 500) reportBug('HIGH', 'SuperAdmin', 'GET /super-admin/rate-limits', 500, b.error, '');
  });

  test('17.14 GET /super-admin/api-keys', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/super-admin/api-keys`, { headers: authHeaders(superAdminToken) });
    const b = await r.json();
    if (r.status() === 500) reportBug('HIGH', 'SuperAdmin', 'GET /super-admin/api-keys', 500, b.error, '');
  });

  test('17.15 GET /super-admin/zones', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/super-admin/zones`, { headers: authHeaders(superAdminToken) });
    const b = await r.json();
    if (r.status() === 500) reportBug('HIGH', 'SuperAdmin', 'GET /super-admin/zones', 500, b.error, '');
  });

  test('17.16 GET /super-admin/organizations', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/super-admin/organizations`, { headers: authHeaders(superAdminToken) });
    const b = await r.json();
    if (r.status() === 500) reportBug('HIGH', 'SuperAdmin', 'GET /super-admin/organizations', 500, b.error, '');
  });

  test('17.17 GET /super-admin/resellers', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/super-admin/resellers`, { headers: authHeaders(superAdminToken) });
    const b = await r.json();
    if (r.status() === 500) reportBug('HIGH', 'SuperAdmin', 'GET /super-admin/resellers', 500, b.error, '');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION 18: CROSS-APP — Role enforcement
  // ═══════════════════════════════════════════════════════════════════════════
  test('18.1 Player cannot access /manage/dashboard', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/manage/dashboard`, { headers: authHeaders(playerToken) });
    if (r.ok()) {
      reportBug('CRITICAL', 'Cross-App', 'GET /manage/dashboard', 200, 'player can access manager dashboard', 'Role enforcement broken — player should get 403');
    }
  });

  test('18.2 Player cannot access /admin/dashboard', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/admin/dashboard`, { headers: authHeaders(playerToken) });
    if (r.ok()) {
      reportBug('CRITICAL', 'Cross-App', 'GET /admin/dashboard', 200, 'player can access admin dashboard', 'Role enforcement broken — player should get 403');
    }
  });

  test('18.3 Manager cannot access /admin/users', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/admin/users`, { headers: authHeaders(managerToken) });
    if (r.ok()) {
      reportBug('CRITICAL', 'Cross-App', 'GET /admin/users', 200, 'manager can access admin users', 'Role enforcement broken — manager should get 403');
    }
  });

  test('18.4 Unauthenticated cannot access /bookings/me', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/bookings/me`);
    if (r.ok()) {
      reportBug('CRITICAL', 'Cross-App', 'GET /bookings/me (no auth)', 200, 'accessible without auth', 'Auth middleware broken');
    }
  });

  test('18.5 Unauthenticated cannot access /users/me', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/users/me`);
    if (r.ok()) {
      reportBug('CRITICAL', 'Cross-App', 'GET /users/me (no auth)', 200, 'accessible without auth', 'Auth middleware broken');
    }
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION 19: FLUTTER WEB — Page loads
  // ═══════════════════════════════════════════════════════════════════════════
  test('19.1 Player app loads (port 3000)', async ({ page }) => {
    const resp = await page.goto('http://localhost:3000/', { waitUntil: 'domcontentloaded', timeout: 15000 });
    if (!resp || !resp.ok()) {
      reportBug('CRITICAL', 'Player', 'Player App Load', resp?.status() || 0, 'page did not load', '');
    }
  });

  test('19.2 Turf Manager app loads (port 3002)', async ({ page }) => {
    const resp = await page.goto('http://localhost:3002/', { waitUntil: 'domcontentloaded', timeout: 15000 });
    if (!resp || !resp.ok()) {
      reportBug('CRITICAL', 'Manager', 'Manager App Load', resp?.status() || 0, 'page did not load', '');
    }
  });

  test('19.3 Super Admin app loads (port 3003)', async ({ page }) => {
    const resp = await page.goto('http://localhost:3003/', { waitUntil: 'domcontentloaded', timeout: 15000 });
    if (!resp || !resp.ok()) {
      reportBug('CRITICAL', 'SuperAdmin', 'SuperAdmin App Load', resp?.status() || 0, 'page did not load', '');
    }
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // MAP FLOW — Pitch discovery API
  // ═══════════════════════════════════════════════════════════════════════════
  test.describe('Map Flow — Pitch discovery API', () => {

    test('GET /pitches?lat&lng&radius — nearby pitches', async ({ request }) => {
      const endpoint = 'GET /pitches?lat=22.3569&lng=91.7832&radius=5';
      const r = await request.get(`${API}/api/v1/pitches?lat=22.3569&lng=91.7832&radius=5`, {
        headers: authHeaders(playerToken),
      });
      const b = await r.json();
      if (!r.ok()) {
        reportBug('HIGH', 'API', endpoint, r.status(), 'nearby pitch geo-query failed', JSON.stringify(b));
      }
      expect(r.ok()).toBeTruthy();
      expect(b).toHaveProperty('data');
      expect(Array.isArray(b.data)).toBe(true);
    });

    test('GET /pitches?city — city-filtered pitch list', async ({ request }) => {
      const endpoint = 'GET /pitches?city=Chittagong';
      const r = await request.get(`${API}/api/v1/pitches?city=Chittagong`, {
        headers: authHeaders(playerToken),
      });
      const b = await r.json();
      if (!r.ok()) {
        reportBug('HIGH', 'API', endpoint, r.status(), 'city-filter query failed', JSON.stringify(b));
      }
      expect(r.ok()).toBeTruthy();
      expect(b).toHaveProperty('data');
      expect(Array.isArray(b.data)).toBe(true);
    });

    test('GET /pitches?lat&lng&radius=25 — large radius filter', async ({ request }) => {
      const endpoint = 'GET /pitches?lat=23.8103&lng=90.4125&radius=25';
      const r = await request.get(`${API}/api/v1/pitches?lat=23.8103&lng=90.4125&radius=25`, {
        headers: authHeaders(playerToken),
      });
      const b = await r.json();
      if (!r.ok()) {
        reportBug('HIGH', 'API', endpoint, r.status(), 'large-radius geo-query failed', JSON.stringify(b));
      }
      expect(r.ok()).toBeTruthy();
      expect(b).toHaveProperty('data');
      expect(Array.isArray(b.data)).toBe(true);
    });

    test('GET /pitches?search — text search', async ({ request }) => {
      const endpoint = 'GET /pitches?search=arena';
      const r = await request.get(`${API}/api/v1/pitches?search=arena`, {
        headers: authHeaders(playerToken),
      });
      const b = await r.json();
      if (!r.ok()) {
        reportBug('HIGH', 'API', endpoint, r.status(), 'text search query failed', JSON.stringify(b));
      }
      expect(r.ok()).toBeTruthy();
      expect(b).toHaveProperty('data');
      expect(Array.isArray(b.data)).toBe(true);
    });

  });

  // ═══════════════════════════════════════════════════════════════════════════
  // FINAL: Generate bug report
  // ═══════════════════════════════════════════════════════════════════════════
  test('REPORT: write BUG-REPORT.md', async () => {
    const lines: string[] = [
      '# Turfinn E2E Bug Report',
      '',
      `**Date:** ${new Date().toISOString().split('T')[0]}`,
      `**Tested by:** Playwright E2E — full-stack-audit.spec.ts`,
      `**Environment:** Docker Compose (localhost)`,
      `**Scope:** Player App + Turf Manager + Super Admin + Cross-App`,
      '',
      `**Total bugs found:** ${bugs.length}`,
      '',
    ];

    if (bugs.length === 0) {
      lines.push('## No bugs found');
      lines.push('');
      lines.push('All endpoints working correctly across all three apps.');
    } else {
      // Group by severity
      const severities = ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW'];
      for (const sev of severities) {
        const sevBugs = bugs.filter(b => b.severity === sev);
        if (sevBugs.length === 0) continue;

        lines.push(`---`);
        lines.push('');
        lines.push(`## ${sev} (${sevBugs.length})`);
        lines.push('');

        for (const b of sevBugs) {
          lines.push(`### BUG-${b.id}: \`${b.endpoint}\` [${b.app}]`);
          lines.push('');
          lines.push(`- **Status:** ${b.status}`);
          lines.push(`- **Error:** ${b.error}`);
          if (b.detail) lines.push(`- **Detail:** ${b.detail}`);
          lines.push('');
        }
      }

      // Summary table
      lines.push('---');
      lines.push('');
      lines.push('## Summary');
      lines.push('');
      lines.push('| Severity | Count |');
      lines.push('|----------|-------|');
      for (const sev of severities) {
        const count = bugs.filter(b => b.severity === sev).length;
        if (count > 0) lines.push(`| ${sev} | ${count} |`);
      }
      lines.push(`| **Total** | **${bugs.length}** |`);
      lines.push('');

      // By app
      lines.push('| App | Bugs |');
      lines.push('|-----|------|');
      const apps = [...new Set(bugs.map(b => b.app))];
      for (const app of apps) {
        lines.push(`| ${app} | ${bugs.filter(b => b.app === app).length} |`);
      }
    }

    const fs = require('fs');
    const reportPath = '/Users/fin.com/Projects/brain-systems/turfinn/BUG-REPORT.md';
    fs.writeFileSync(reportPath, lines.join('\n') + '\n');

    console.log(`\n=== BUG REPORT: ${bugs.length} bugs found ===`);
    for (const b of bugs) {
      console.log(`  BUG-${b.id} [${b.severity}][${b.app}] ${b.endpoint} -> ${b.status}: ${b.error}`);
    }
  });
});
