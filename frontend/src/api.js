const API_URL = import.meta.env.VITE_API_BASE_URL || '/api';


export async function getHabits() {
  const res = await fetch(`${API_URL}/habits`);
  return res.json();
}

export async function createHabit(habit) {
  const res = await fetch(`${API_URL}/habits`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(habit)
  });
  return res.json();
}

export async function addEntry(habitId, date, value) {
  const res = await fetch(`${API_URL}/habits/${habitId}/entries`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ date, value })
  });
  return res.json();
}

export async function deleteHabit(habitId) {
  await fetch(`${API_URL}/habits/${habitId}`, { method: 'DELETE' });
}