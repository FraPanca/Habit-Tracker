import { describe, it, expect } from 'vitest';
import mongoose from 'mongoose';
import Entry from '../../src/models/Entry.js';

const fakeHabitId = new mongoose.Types.ObjectId();

describe('Entry model', () => {
  it('crea un entry valido con i campi minimi richiesti', async () => {
    const entry = await Entry.create({ habitId: fakeHabitId, date: '2026-08-20', value: true });

    expect(entry.habitId).toBe(fakeHabitId);
    expect(entry.date).toBe('2026-08-20');
    expect(entry.value).toBe(true);
    expect(entry.notedAt).toBeInstanceOf(Date);
  });

  it('rifiuta un entry senza habitId', async () => {
    await expect(
      Entry.create({ date: '2026-08-20', value: true })
    ).rejects.toThrow();
  });

  it('rifiuta un entry senza date', async () => {
    await expect(
      Entry.create({ habitId: fakeHabitId, value: true })
    ).rejects.toThrow();
  });

  it('rifiuta un entry senza value', async () => {
    await expect(
      Entry.create({ habitId: fakeHabitId, date: '2026-08-20' })
    ).rejects.toThrow();
  });

  it('rifiuta un value che non è "boolean" né "numeric"', async () => {
    await expect(
      Entry.create({ habitId: fakeHabitId, date: '2026-08-20', value: 'abc' })
    ).rejects.toThrow();
  });

  it('accetta value per entry numerici', async () => {
    const entry = await Entry.create({
      habitId: fakeHabitId,
      date: '2026-08-20',
      value: 8
    });

    expect(entry.value).toBe(8);
  });

  it('rispetta l\'unicità dell\'indice', async () => {
    const entry = await Entry.create({ habitId: fakeHabitId, date: '2026-08-20', value: true });
    await expect(
      Entry.create({ habitId: fakeHabitId, date: '2026-08-20', value: 'false' })
    ).rejects.toThrow();
  });

  it('accetta due entry con stesso id e date diverse', async () => {
    const entry1 = await Entry.create({ habitId: fakeHabitId, date: '2026-08-19', value: true });
    const entry2 = await Entry.create({ habitId: fakeHabitId, date: '2026-08-20', value: true });

    expect(entry1.habitId).toBe(fakeHabitId);
    expect(entry1.date).toBe('2026-08-19');
    expect(entry2.habitId).toBe(fakeHabitId);
    expect(entry2.date).toBe('2026-08-20');
  });
});