import { useState, useEffect } from 'react';
import { getHabits, createHabit, addEntry, deleteHabit } from './api';
import './App.css';

const today = () => new Date().toISOString().split('T')[0];


function App() {
  const [habits, setHabits] = useState([]);
  const [name, setName] = useState('');
  const [type, setType] = useState('boolean');
  const [targetValue, setTargetValue] = useState('');
  const [numericInputs, setNumericInputs] = useState({});
  const [error, setError] = useState(null);

  useEffect(() => {
    loadHabits();
  }, []);

  async function loadHabits() {
    try {
      const data = await getHabits();
      setHabits(data);
      setError(null);
    } catch (err) {
      console.error('Errore nel caricamento delle abitudini:', err);
      setError('Impossibile caricare le abitudini. Riprova più tardi.');
    }
  }

  async function handleCreate(e) {
    e.preventDefault();
    if (!name.trim()) return;
    try {
      const payload = { name, type };
      if (type === 'numeric' && targetValue !== '') {
        payload.targetValue = Number(targetValue);
      }
      await createHabit(payload);
      setName('');
      setType('boolean');
      setTargetValue('');
      loadHabits();
    } catch (err) {
      console.error('Errore nella creazione dell\'abitudine:', err);
      setError('Impossibile creare l\'abitudine. Riprova.');
    }
  }

  async function handleCheck(habitId) {
    try {
      await addEntry(habitId, today(), true);
      alert('Registrato per oggi!');
    } catch (err) {
      console.error('Errore nella registrazione:', err);
      setError('Impossibile registrare l\'abitudine di oggi.');
    }
  }

  async function handleNumericSubmit(habitId) {
    const raw = numericInputs[habitId];
    const value = Number(raw);
    if (raw === undefined || raw === '' || Number.isNaN(value)) return;
    try {
      await addEntry(habitId, today(), value);
      setNumericInputs((prev) => ({ ...prev, [habitId]: '' }));
      alert('Registrato per oggi!');
    } catch (err) {
      console.error('Errore nella registrazione:', err);
      setError('Impossibile registrare l\'abitudine di oggi.');
    }
  }

  async function handleDelete(habitId) {
    try {
      await deleteHabit(habitId);
      loadHabits();
    } catch (err) {
      console.error('Errore nell\'eliminazione:', err);
      setError('Impossibile eliminare l\'abitudine.');
    }
  }

  return (
    <div className="app">
      <h1>Habit Tracker</h1>

      {error && (
        <div className="error-banner" role="alert">
          {error}
        </div>
      )}

      <form onSubmit={handleCreate} className="habit-form">
        <input
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="Nuova abitudine (es. Bere 2L acqua)"
        />
        <select value={type} onChange={(e) => setType(e.target.value)}>
          <option value="boolean">Sì/No</option>
          <option value="numeric">Numerica</option>
        </select>
        {type === 'numeric' && (
          <input
            type="number"
            value={targetValue}
            onChange={(e) => setTargetValue(e.target.value)}
            placeholder="Obiettivo (opz.)"
            className="target-input"
          />
        )}
        <button type="submit">Aggiungi</button>
      </form>

      <ul className="habit-list">
        {habits.map((h) => (
          <li key={h._id} className="habit-item">
            <span>
              {h.name}
              {h.type === 'numeric' && h.targetValue ? ` (obiettivo: ${h.targetValue})` : ''}
            </span>
            <div className="habit-actions">
              {h.type === 'numeric' ? (
                <>
                  <input
                    type="number"
                    className="numeric-input"
                    value={numericInputs[h._id] ?? ''}
                    onChange={(e) =>
                      setNumericInputs((prev) => ({ ...prev, [h._id]: e.target.value }))
                    }
                    placeholder="Valore di oggi"
                  />
                  <button className="done-btn" onClick={() => handleNumericSubmit(h._id)}>
                    Registra
                  </button>
                </>
              ) : (
                <button className="done-btn" onClick={() => handleCheck(h._id)}>✓ Fatto oggi</button>
              )}
              <button className="delete-btn" onClick={() => handleDelete(h._id)}>🗑</button>
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
}


export default App;