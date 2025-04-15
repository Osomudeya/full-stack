import React, { useState, useEffect } from 'react';
import Game from './components/Game';
import Leaderboard from './components/Leaderboard';
import './App.css';

function App() {
  const [scores, setScores] = useState([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState(null);
  const [playerName, setPlayerName] = useState('');
  const [isPlaying, setIsPlaying] = useState(false);

  // API URL based on environment
  const API_URL = process.env.REACT_APP_API_URL || 'http://localhost:3001';

  // Fetch leaderboard data
  const fetchLeaderboard = async () => {
    setIsLoading(true);
    try {
      const response = await fetch(`${API_URL}/api/scores`);
      if (!response.ok) {
        throw new Error(`Error: ${response.status}`);
      }
      const data = await response.json();
      setScores(data);
    } catch (err) {
      console.error('Failed to fetch leaderboard:', err);
      setError('Failed to load leaderboard. Please try again later.');
    } finally {
      setIsLoading(false);
    }
  };

  // Save score to the backend
  const saveScore = async (score, time) => {
    try {
      const response = await fetch(`${API_URL}/api/scores`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ playerName, score, time }),
      });

      if (!response.ok) {
        throw new Error(`Error: ${response.status}`);
      }

      // Refresh leaderboard after saving
      fetchLeaderboard();
    } catch (err) {
      console.error('Failed to save score:', err);
      setError('Failed to save your score. Please try again.');
    }
  };

  // Fetch leaderboard on component mount
  useEffect(() => {
    fetchLeaderboard();
  }, []);

  // Handle game completion
  const handleGameComplete = (score, time) => {
    if (playerName) {
      saveScore(score, time);
    }
    setIsPlaying(false);
  };

  // Start a new game
  const startGame = () => {
    if (!playerName) {
      setError('Please enter your name to play');
      return;
    }
    setError(null);
    setIsPlaying(true);
  };

  return (
    <div className="app">
      <header>
        <h1>Memory Card Game</h1>
        <p>Match all the cards to win!</p>
      </header>

      <main>
        {!isPlaying ? (
          <div className="welcome-screen">
            <h2>Welcome to Memory Match</h2>
            <div className="player-form">
              <input
                type="text"
                placeholder="Enter your name"
                value={playerName}
                onChange={(e) => setPlayerName(e.target.value)}
              />
              <button onClick={startGame}>Start Game</button>
            </div>
            {error && <p className="error">{error}</p>}
            
            <Leaderboard scores={scores} isLoading={isLoading} />
          </div>
        ) : (
          <Game onGameComplete={handleGameComplete} />
        )}
      </main>

      <footer>
        <p>© 2025 Memory Card Game - Kubernetes Monitoring Demo</p>
      </footer>
    </div>
  );
}

export default App;