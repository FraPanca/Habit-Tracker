import { describe, it, expect } from 'vitest';
import request from 'supertest';
import mongoose from 'mongoose';
import app from '../../src/app.js';

const fakeHabitId = new mongoose.Types.ObjectId();


describe('POST /api/habits', () => {
  it('crea una nuova abitudine e risponde 201', async () => {
    const res = await request(app).post('/api/habits').send({ name: 'Bere acqua', type: 'boolean' });

    expect(res.status).toBe(201);
    expect(res.body.name).toBe('Bere acqua');
    expect(res.body._id).toBeDefined();
  });

  it('risponde 400 se manca il campo name', async () => {
    const res = await request(app)
      .post('/api/habits')
      .send({ type: 'boolean' });

    expect(res.status).toBe(400);
  });
});

describe('GET /api/habits', () => {
  it('restituisce array vuoto quando non ci sono habit', async () => {
    const res = await request(app).get('/api/habits');

    expect(res.status).toBe(200);
    expect(res.body).toEqual([]);
  });

  it('restituisce gli habit creati', async () => {
    await request(app).post('/api/habits').send({ name: 'Test', type: 'boolean' });

    const res = await request(app).get('/api/habits');

    expect(res.status).toBe(200);
    expect(res.body).toHaveLength(1);
    expect(res.body[0].name).toBe('Test');
  });
});

describe('POST /api/habits/:id/entries', () => {
  it('crea una nuova entry e risponde 201', async () => {
    const habitRes = await request(app).post('/api/habits').send({ name: 'Bere acqua', type: 'boolean' });

    const habitId = habitRes.body._id;

    const res = await request(app).post(`/api/habits/${habitId}/entries`).send({ date: '2026-08-20', value: true });

    expect(res.status).toBe(201);
    expect(res.body.habitId).toBe(habitId);
    expect(res.body.date).toBe('2026-08-20');
    expect(res.body.value).toBe(true);
  });

  it('aggiorna (upsert) invece di duplicare se chiamato due volte con la stessa date', async () => {
    const habitRes = await request(app).post('/api/habits').send({ name: 'Studio', type: 'boolean' });

    const habitId = habitRes.body._id;

    await request(app).post(`/api/habits/${habitId}/entries`).send({ date: '2026-08-20', value: true });

    await request(app).post(`/api/habits/${habitId}/entries`).send({ date: '2026-08-20', value: false });

    const historyRes = await request(app).get(`/api/habits/${habitId}/entries`);

    expect(historyRes.body).toHaveLength(1);
    expect(historyRes.body[0].value).toBe(false); // l'ultimo valore ha sovrascritto il primo
  });
});

describe('GET /api/habits/:id/entries', () => {
  it('restituisce lo storico corretto', async () => {
    const habitRes = await request(app).post('/api/habits').send({ name: 'Palestra', type: 'boolean' });

    const habitId = habitRes.body._id;

    await request(app).post(`/api/habits/${habitId}/entries`).send({ date: '2026-08-18', value: true });
    await request(app).post(`/api/habits/${habitId}/entries`).send({ date: '2026-08-19', value: false });

    const res = await request(app).get(`/api/habits/${habitId}/entries`);

    expect(res.status).toBe(200);
    expect(res.body).toHaveLength(2);
  });
});

describe('DELETE /api/habits/:id', () => {
  it('elimina un habit e risponde 204', async () => {
    const habitRes = await request(app).post('/api/habits').send({ name: 'Da eliminare', type: 'boolean' });

    const habitId = habitRes.body._id;

    const deleteRes = await request(app).delete(`/api/habits/${habitId}`);
    expect(deleteRes.status).toBe(204);

    const listRes = await request(app).get('/api/habits');
    expect(listRes.body).toHaveLength(0);
  });
});