import { useState, useEffect } from 'react';
import { getHabits, createHabit, addEntry, deleteHabit } from './api';
import './App.css';

const today = () => new Date().toISOString().split('T')[0];


function App() {
  const [habits, setHabits] = useState([]);
  const [name, setName] = useState('');
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
      await createHabit({ name, type: 'boolean' });
      setName('');
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
        <button type="submit">Aggiungi</button>
      </form>

      <ul className="habit-list">
        {habits.map((h) => (
          <li key={h._id} className="habit-item">
            <span>{h.name}</span>
            <div className="habit-actions">
              <button className="done-btn" onClick={() => handleCheck(h._id)}>✓ Fatto oggi</button>
              <button className="delete-btn" onClick={() => handleDelete(h._id)}>🗑</button>
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
}


export default App;