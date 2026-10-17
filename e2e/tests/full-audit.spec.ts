import { test, expect } from '@playwright/test';

const API = 'http://localhost:8080';
let token = '';
let pitchId = '';
let bookingId = '';
let teamId = '';
let teamCode = '';
let tournamentId = '';

// Helper: get auth token with unique phone to avoid rate limits
async function getToken(request: any, phone: string) {
  const otpResp = await request.post(`${API}/api/v1/auth/send-otp`, {
    data: { phone },
  });
  const otpBody = await otpResp.json();
  if (!otpBody.data?.otp_dev) {
    return { token: '', error: `OTP send failed for ${phone}: ${JSON.stringify(otpBody)}` };
  }
  const verifyResp = await request.post(`${API}/api/v1/auth/verify-otp`, {
    data: { phone, otp: otpBody.data.otp_dev },
  });
  const verifyBody = await verifyResp.json();
  return { token: verifyBody.data?.token || '', error: verifyBody.data?.token ? '' : JSON.stringify(verifyBody) };
}

const bugs: { endpoint: string; status: number; error: string; detail: string }[] = [];

function reportBug(endpoint: string, status: number, error: string, detail: string) {
  bugs.push({ endpoint, status, error, detail });
  console.log(`BUG: ${endpoint} → ${status} — ${error} — ${detail}`);
}

test.describe.serial('Full API Audit', () => {
  test('setup: authenticate', async ({ request }) => {
    // Use unique phone per run to avoid OTP rate limit (5/min)
    const phone = `+88017${Date.now().toString().slice(-8)}`;
    const result = await getToken(request, phone);
    expect(result.error).toBe('');
    token = result.token;
  });

  test('GET /health', async ({ request }) => {
    const r = await request.get(`${API}/health`);
    expect(r.ok()).toBeTruthy();
  });

  // ── Auth ──
  test('POST /auth/send-otp', async ({ request }) => {
    const r = await request.post(`${API}/api/v1/auth/send-otp`, { data: { phone: '+8801799900010' } });
    const b = await r.json();
    if (!r.ok()) reportBug('POST /auth/send-otp', r.status(), b.error, 'OTP send failed');
    expect(r.ok()).toBeTruthy();
  });

  test('POST /auth/verify-otp', async ({ request }) => {
    const otp = await request.post(`${API}/api/v1/auth/send-otp`, { data: { phone: '+8801799900011' } });
    const ob = await otp.json();
    const r = await request.post(`${API}/api/v1/auth/verify-otp`, {
      data: { phone: '+8801799900011', otp: ob.data.otp_dev },
    });
    const b = await r.json();
    if (!r.ok()) reportBug('POST /auth/verify-otp', r.status(), b.error, 'OTP verify failed');
    expect(r.ok()).toBeTruthy();
  });

  // ── User ──
  test('GET /users/me', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/users/me`, { headers: { Authorization: `Bearer ${token}` } });
    const b = await r.json();
    if (!r.ok()) reportBug('GET /users/me', r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
    expect(b.data).toHaveProperty('id');
  });

  test('PUT /users/me', async ({ request }) => {
    const r = await request.put(`${API}/api/v1/users/me`, {
      headers: { Authorization: `Bearer ${token}` },
      data: { name: 'E2E Tester', position: 'Midfielder', skill_level: 'Intermediate' },
    });
    const b = await r.json();
    if (!r.ok()) reportBug('PUT /users/me', r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
  });

  // ── Pitches ──
  test('GET /pitches', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/pitches`);
    const b = await r.json();
    if (!r.ok()) reportBug('GET /pitches', r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
    expect(b.data.length).toBeGreaterThan(0);
    pitchId = b.data[0].id;
  });

  test('GET /pitches/:id', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/pitches/${pitchId}`);
    const b = await r.json();
    if (!r.ok()) reportBug(`GET /pitches/${pitchId}`, r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
  });

  test('GET /pitches/:id/slots', async ({ request }) => {
    const today = new Date().toISOString().split('T')[0];
    const r = await request.get(`${API}/api/v1/pitches/${pitchId}/slots?date=${today}`);
    const b = await r.json();
    if (!r.ok()) reportBug(`GET /pitches/:id/slots`, r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
  });

  // ── Profile & Wallet ──
  test('GET /profile', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/profile`, { headers: { Authorization: `Bearer ${token}` } });
    const b = await r.json();
    if (!r.ok()) reportBug('GET /profile', r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
    // Validate all gamification fields exist
    for (const field of ['xp', 'level', 'level_title', 'xp_to_next_level', 'coins_balance', 'current_streak', 'referral_code', 'badges']) {
      if (!(field in b.data)) reportBug('GET /profile', 200, `missing field: ${field}`, JSON.stringify(Object.keys(b.data)));
    }
  });

  test('GET /wallet', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/wallet`, { headers: { Authorization: `Bearer ${token}` } });
    const b = await r.json();
    if (!r.ok()) reportBug('GET /wallet', r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
  });

  test('GET /wallet/transactions', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/wallet/transactions`, { headers: { Authorization: `Bearer ${token}` } });
    const b = await r.json();
    if (!r.ok()) reportBug('GET /wallet/transactions', r.status(), b.error, `DB schema mismatch: table has user_id+amount_paisa+description+ref_id but GORM entity expects wallet_id+amount+type+reference`);
    // Don't assert ok — this is a known bug we're documenting
  });

  // ── Gamification ──
  test('GET /checkin/status', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/checkin/status`, { headers: { Authorization: `Bearer ${token}` } });
    const b = await r.json();
    if (!r.ok()) reportBug('GET /checkin/status', r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
  });

  test('POST /checkin', async ({ request }) => {
    const r = await request.post(`${API}/api/v1/checkin`, { headers: { Authorization: `Bearer ${token}` } });
    const b = await r.json();
    // OK or "already checked in" — both valid
    if (!r.ok() && !b.error?.includes('already checked in')) {
      reportBug('POST /checkin', r.status(), b.error, '');
    }
  });

  test('GET /challenges', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/challenges`, { headers: { Authorization: `Bearer ${token}` } });
    const b = await r.json();
    if (!r.ok()) reportBug('GET /challenges', r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
  });

  test('GET /leaderboard', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/leaderboard`, { headers: { Authorization: `Bearer ${token}` } });
    const b = await r.json();
    if (!r.ok()) reportBug('GET /leaderboard', r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
  });

  test('GET /leaderboard/previous', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/leaderboard/previous`, { headers: { Authorization: `Bearer ${token}` } });
    const b = await r.json();
    if (!r.ok()) reportBug('GET /leaderboard/previous', r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
  });

  test('GET /referral', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/referral`, { headers: { Authorization: `Bearer ${token}` } });
    const b = await r.json();
    if (!r.ok()) reportBug('GET /referral', r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
  });

  test('POST /store/streak-freeze (no streak)', async ({ request }) => {
    const r = await request.post(`${API}/api/v1/store/streak-freeze`, { headers: { Authorization: `Bearer ${token}` } });
    const b = await r.json();
    // Should fail gracefully (no streak record or insufficient coins)
    if (r.ok()) reportBug('POST /store/streak-freeze', 200, 'unexpected success', 'should fail for new user with 0 coins');
  });

  // ── Feed ──
  test('GET /feed', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/feed`, { headers: { Authorization: `Bearer ${token}` } });
    const b = await r.json();
    if (!r.ok()) reportBug('GET /feed', r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
  });

  test('POST /feed (create post)', async ({ request }) => {
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    tomorrow.setHours(18, 0, 0, 0);
    const r = await request.post(`${API}/api/v1/feed`, {
      headers: { Authorization: `Bearer ${token}` },
      data: {
        pitch_id: pitchId,
        title: 'E2E Test Match',
        description: 'Looking for players',
        match_date: tomorrow.toISOString(),
        spots_total: 10,
      },
    });
    const b = await r.json();
    if (!r.ok()) reportBug('POST /feed', r.status(), b.error, JSON.stringify(b));
  });

  // ── Bookings ──
  test('POST /bookings (create)', async ({ request }) => {
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 2);
    tomorrow.setHours(14, 0, 0, 0);
    const startsAt = tomorrow.toISOString();
    const endsAt = new Date(tomorrow.getTime() + 60 * 60 * 1000).toISOString();

    const r = await request.post(`${API}/api/v1/bookings`, {
      headers: { Authorization: `Bearer ${token}` },
      data: { pitch_id: pitchId, starts_at: startsAt, ends_at: endsAt },
    });
    const b = await r.json();
    if (!r.ok()) reportBug('POST /bookings', r.status(), b.error, JSON.stringify(b));
    else bookingId = b.data.id;
  });

  test('GET /bookings/me', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/bookings/me`, { headers: { Authorization: `Bearer ${token}` } });
    const b = await r.json();
    if (!r.ok()) reportBug('GET /bookings/me', r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
  });

  test('DELETE /bookings/:id (cancel)', async ({ request }) => {
    if (!bookingId) return;
    const r = await request.delete(`${API}/api/v1/bookings/${bookingId}`, { headers: { Authorization: `Bearer ${token}` } });
    const b = await r.json();
    if (!r.ok()) reportBug(`DELETE /bookings/${bookingId}`, r.status(), b.error, '');
  });

  // ── Teams ──
  test('POST /teams (create)', async ({ request }) => {
    const r = await request.post(`${API}/api/v1/teams`, {
      headers: { Authorization: `Bearer ${token}` },
      data: { name: 'E2E Squad', format: '5 vs 5', formation: '2-1-1' },
    });
    const b = await r.json();
    if (!r.ok()) reportBug('POST /teams', r.status(), b.error, JSON.stringify(b));
    else {
      teamId = b.data.id;
      teamCode = b.data.code;
    }
  });

  test('GET /teams/me', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/teams/me`, { headers: { Authorization: `Bearer ${token}` } });
    const b = await r.json();
    if (!r.ok()) reportBug('GET /teams/me', r.status(), b.error, 'Route may be matching /:id instead of /me');
  });

  test('GET /teams/:id', async ({ request }) => {
    if (!teamId) return;
    const r = await request.get(`${API}/api/v1/teams/${teamId}`, { headers: { Authorization: `Bearer ${token}` } });
    const b = await r.json();
    if (!r.ok()) reportBug(`GET /teams/${teamId}`, r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
  });

  // ── Tournaments ──
  test('POST /tournaments (create)', async ({ request }) => {
    const r = await request.post(`${API}/api/v1/tournaments`, {
      headers: { Authorization: `Bearer ${token}` },
      data: { name: 'E2E Cup', format: '5 vs 5', max_teams: 4, entry_fee: 0, min_coins: 0, visibility: 'public' },
    });
    const b = await r.json();
    if (!r.ok()) reportBug('POST /tournaments', r.status(), b.error, JSON.stringify(b));
    else tournamentId = b.data.id;
  });

  test('GET /tournaments', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/tournaments`, { headers: { Authorization: `Bearer ${token}` } });
    const b = await r.json();
    if (!r.ok()) reportBug('GET /tournaments', r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
  });

  test('GET /tournaments/:id', async ({ request }) => {
    if (!tournamentId) return;
    const r = await request.get(`${API}/api/v1/tournaments/${tournamentId}`, { headers: { Authorization: `Bearer ${token}` } });
    const b = await r.json();
    if (!r.ok()) reportBug(`GET /tournaments/${tournamentId}`, r.status(), b.error, '');
    expect(r.ok()).toBeTruthy();
    // Validate bracket structure
    if (b.data.matches && !Array.isArray(b.data.matches)) reportBug('GET /tournaments/:id', 200, 'matches is not array', typeof b.data.matches);
    if (b.data.teams && !Array.isArray(b.data.teams)) reportBug('GET /tournaments/:id', 200, 'teams is not array', typeof b.data.teams);
  });

  test('POST /tournaments/:id/join', async ({ request }) => {
    if (!tournamentId || !teamId) return;
    const r = await request.post(`${API}/api/v1/tournaments/${tournamentId}/join`, {
      headers: { Authorization: `Bearer ${token}` },
      data: { team_id: teamId },
    });
    const b = await r.json();
    if (!r.ok()) reportBug('POST /tournaments/:id/join', r.status(), b.error, JSON.stringify(b));
  });

  test('POST /tournaments/:id/start (should fail — only 1 team)', async ({ request }) => {
    if (!tournamentId) return;
    const r = await request.post(`${API}/api/v1/tournaments/${tournamentId}/start`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    const b = await r.json();
    // Should fail because only 1 team registered
    if (r.ok()) reportBug('POST /tournaments/:id/start', 200, 'started with 1 team', 'should require >= 2');
    if (r.status() !== 400) reportBug('POST /tournaments/:id/start', r.status(), b.error, 'expected 400');
  });

  test('POST /tournaments/:id/cancel', async ({ request }) => {
    if (!tournamentId) return;
    const r = await request.post(`${API}/api/v1/tournaments/${tournamentId}/cancel`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    const b = await r.json();
    if (!r.ok()) reportBug('POST /tournaments/:id/cancel', r.status(), b.error, JSON.stringify(b));
  });

  // ── Config/Public ──
  test('GET /config', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/config`);
    const b = await r.json();
    if (!r.ok()) reportBug('GET /config', r.status(), b.error, '');
  });

  test('GET /banners', async ({ request }) => {
    const r = await request.get(`${API}/api/v1/banners`);
    const b = await r.json();
    if (!r.ok()) reportBug('GET /banners', r.status(), b.error, '');
  });

  // ── Final Report ──
  test('REPORT: write bug report', async () => {
    const report = [
      '# Turfinn E2E Bug Report',
      '',
      `**Date:** ${new Date().toISOString().split('T')[0]}`,
      `**Total bugs found:** ${bugs.length}`,
      '',
      '---',
      '',
    ];

    if (bugs.length === 0) {
      report.push('No bugs found! All endpoints working correctly.');
    } else {
      report.push('| # | Endpoint | Status | Error | Detail |');
      report.push('|---|---|---|---|---|');
      bugs.forEach((b, i) => {
        report.push(`| ${i + 1} | \`${b.endpoint}\` | ${b.status} | ${b.error} | ${b.detail.slice(0, 100)} |`);
      });
    }

    const fs = require('fs');
    fs.writeFileSync('/Users/fin.com/Projects/brain-systems/turfinn/e2e/results/bug-report.md', report.join('\n'));
    console.log(`\n\n=== BUG REPORT: ${bugs.length} bugs found ===\n`);
    bugs.forEach((b, i) => console.log(`  ${i + 1}. ${b.endpoint} → ${b.status}: ${b.error}`));
  });
});
