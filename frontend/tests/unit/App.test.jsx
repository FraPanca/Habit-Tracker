import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import App from '../../src/App';
import * as api from '../../src/api';

// Sostituisce il modulo api.js con versioni mockate per ogni funzione
vi.mock('../../src/api');


describe('App', () => {
  beforeEach(() => {
    vi.clearAllMocks(); // pulisce i mock tra un test e l'altro (stesso principio di isolamento visto nel backend)
  });

  it('mostra la lista di abitudini caricate', async () => {
    api.getHabits.mockResolvedValue([
      { _id: '1', name: 'Bere acqua' },
      { _id: '2', name: 'Studio' },
    ]);

    render(<App />);

    // waitFor perché il caricamento è asincrono (useEffect + await)
    await waitFor(() => {
      expect(screen.getByText('Bere acqua')).toBeInTheDocument();
      expect(screen.getByText('Studio')).toBeInTheDocument();
    });
  });

  it('mostra lista vuota quando non ci sono abitudini', async () => {
    api.getHabits.mockResolvedValue([]);

    render(<App />);

    await waitFor(() => {
      expect(screen.queryByText('Bere acqua')).not.toBeInTheDocument();
    });
  });

  it('crea una nuova abitudine quando si compila il form', async () => {
    api.getHabits.mockResolvedValue([]);
    api.createHabit.mockResolvedValue({ _id: '3', name: 'Nuova abitudine' });

    const user = userEvent.setup();
    render(<App />);

    const input = screen.getByPlaceholderText(/nuova abitudine/i);
    await user.type(input, 'Nuova abitudine');
    await user.click(screen.getByText('Aggiungi'));

    expect(api.createHabit).toHaveBeenCalledWith({ name: 'Nuova abitudine', type: 'boolean' });
  });

  it('elimina un\'abitudine quando si clicca sul cestino', async () => {
    api.getHabits.mockResolvedValue([
      { _id: '1', name: 'Bere acqua' },
    ]);
    api.deleteHabit.mockResolvedValue();

    const user = userEvent.setup();
    render(<App />);

    await waitFor(() => {
      expect(screen.getByText('Bere acqua')).toBeInTheDocument();
    });

    await user.click(screen.getByText('🗑'));

    expect(api.deleteHabit).toHaveBeenCalledWith('1');
  });

  it('mostra un messaggio di errore se il caricamento fallisce', async () => {
    api.getHabits.mockRejectedValue(new Error('Network error'));

    render(<App />);

    await waitFor(() => {
      expect(screen.getByRole('alert')).toBeInTheDocument();
      expect(screen.getByText(/impossibile caricare/i)).toBeInTheDocument();
    });
  });
});