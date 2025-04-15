import React from 'react';

const Leaderboard = ({ scores, isLoading }) => {
  if (isLoading) {
    return <div className="loading">Loading leaderboard...</div>;
  }

  return (
    <div className="leaderboard">
      <h3>Top Scores</h3>
      {scores.length === 0 ? (
        <p>No scores yet. Be the first to play!</p>
      ) : (
        <table>
          <thead>
            <tr>
              <th>Rank</th>
              <th>Player</th>
              <th>Score</th>
              <th>Time</th>
            </tr>
          </thead>
          <tbody>
            {scores.map((score, index) => (
              <tr key={score.id || index}>
                <td>{index + 1}</td>
                <td>{score.player_name}</td>
                <td>{score.score}</td>
                <td>{score.time}s</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
};

export default Leaderboard;