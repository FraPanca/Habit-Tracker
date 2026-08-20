import { describe, it, expect } from 'vitest';
import Habit from '../../src/models/Habit.js';


describe('Habit model', () => {
  it('crea un habit valido con i campi minimi richiesti', async () => {
    const habit = await Habit.create({ name: 'Bere acqua', type: 'boolean' });

    expect(habit.name).toBe('Bere acqua');
    expect(habit.type).toBe('boolean');
    expect(habit.createdAt).toBeInstanceOf(Date);
  });

  it('rifiuta un habit senza name', async () => {
    await expect(
      Habit.create({ type: 'boolean' })
    ).rejects.toThrow();
  });

  it('rifiuta un habit senza type', async () => {
    await expect(
      Habit.create({ name: 'Test' })
    ).rejects.toThrow();
  });

  it('rifiuta un type che non è "boolean" né "numeric"', async () => {
    await expect(
      Habit.create({ name: 'Test', type: 'invalid' })
    ).rejects.toThrow();
  });

  it('accetta targetValue per habit numerici', async () => {
    const habit = await Habit.create({
      name: 'Bicchieri d\'acqua',
      type: 'numeric',
      targetValue: 8,
    });

    expect(habit.targetValue).toBe(8);
  });

  it('rimuove spazi bianchi superflui dal name (trim)', async () => {
    const habit = await Habit.create({ name: '  Studio  ', type: 'boolean' });
    expect(habit.name).toBe('Studio');
  });
});