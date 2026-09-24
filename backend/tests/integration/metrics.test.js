import { describe, it, expect } from 'vitest';
import request from 'supertest';
import mongoose from 'mongoose';
import app from '../../src/app.js';

const fakeHabitId = new mongoose.Types.ObjectId();

async function scrape() {
  const res = await request(app).get('/metrics');
  expect(res.status).toBe(200);
  return res.text;
}

describe('GET /metrics', () => {
  it('espone le metriche in formato Prometheus', async () => {
    const res = await request(app).get('/metrics');

    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/text\/plain/);
    expect(res.text).toContain('# TYPE http_requests_total counter');
    expect(res.text).toContain('# TYPE http_request_duration_seconds histogram');
    expect(res.text).toContain('process_cpu_seconds_total');
  });

  it('usa il template completo della route, non il path con gli ID', async () => {
    await request(app).get(`/api/habits/${fakeHabitId}/entries`); // 404

    const text = await scrape();

    expect(text).toMatch(/route="\/api\/habits\/:id\/entries",status_code="404"/);
    expect(text).not.toContain(fakeHabitId.toString());
  });

  it('mantiene il prefisso della route anche quando l\'errore passa dall\'error handler', async () => {
    await request(app).get('/api/habits/id-non-valido/entries'); // CastError -> 400

    const text = await scrape();

    expect(text).toMatch(/route="\/api\/habits\/:id\/entries",status_code="400"/);
    expect(text).not.toContain('id-non-valido');
  });

  it('raggruppa le richieste senza route in "unmatched" (niente cardinality explosion)', async () => {
    await request(app).get('/wp-admin/setup-config.php');
    await request(app).get('/percorso/casuale/12345');

    const text = await scrape();

    expect(text).toMatch(/route="unmatched",status_code="404"/);
    expect(text).not.toContain('wp-admin');
    expect(text).not.toContain('percorso/casuale');
  });

  it('non conta healthcheck e scrape come traffico applicativo', async () => {
    await request(app).get('/api/health');

    const text = await scrape();

    expect(text).not.toMatch(/route="\/api\/health"/);
    expect(text).not.toMatch(/route="\/metrics"/);
  });

  it('incrementa le metriche di business', async () => {
    const habit = await request(app).post('/api/habits').send({ name: 'Leggere', type: 'boolean' });
    await request(app)
      .post(`/api/habits/${habit.body._id}/entries`)
      .send({ date: '2026-09-22', value: true });

    const text = await scrape();

    expect(text).toMatch(/habit_tracker_habits_created_total\{[^}]*\} [1-9]/);
    expect(text).toMatch(/habit_tracker_entries_recorded_total\{[^}]*\} [1-9]/);
  });
});