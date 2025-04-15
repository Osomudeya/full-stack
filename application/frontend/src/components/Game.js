import React, { useState, useEffect } from 'react';

// Card images - we'll use emoji characters for simplicity
const cardIcons = [
  '🚀', '🎮', '🎯', '🎲', '🎪', '🎭', '🎨', '🎷',
  '🎸', '🎹', '🎺', '🎻', '🎬', '🎤', '🎧', '🎵'
];

const Game = ({ onGameComplete }) => {
  const [cards, setCards] = useState([]);
  const [flipped, setFlipped] = useState([]);
  const [matched, setMatched] = useState([]);
  const [moves, setMoves] = useState(0);
  const [startTime, setStartTime] = useState(null);
  const [gameTime, setGameTime] = useState(0);
  const [isGameOver, setIsGameOver] = useState(false);
  
  // Initialize game
  useEffect(() => {
    initializeGame();
  }, []);
  
  // Timer effect
  useEffect(() => {
    let timerId;
    if (startTime && !isGameOver) {
      timerId = setInterval(() => {
        const elapsedSeconds = Math.floor((Date.now() - startTime) / 1000);
        setGameTime(elapsedSeconds);
      }, 1000);
    }
    
    return () => {
      if (timerId) clearInterval(timerId);
    };
  }, [startTime, isGameOver]);

  // Check if game is over
  useEffect(() => {
    if (matched.length > 0 && matched.length === cards.length) {
      endGame();
    }
  }, [matched, cards]);

  // Initialize game
  const initializeGame = () => {
    // Create pairs of cards
    const cardPairs = [...cardIcons, ...cardIcons];
    
    // Shuffle cards
    const shuffledCards = cardPairs
      .sort(() => Math.random() - 0.5)
      .map((icon, index) => ({
        id: index,
        icon,
        isFlipped: false,
        isMatched: false
      }));
    
    setCards(shuffledCards);
    setFlipped([]);
    setMatched([]);
    setMoves(0);
    setStartTime(Date.now());
    setGameTime(0);
    setIsGameOver(false);
  };

  // End game
  const endGame = () => {
    setIsGameOver(true);
    const finalScore = calculateScore();
    // Return score and time to parent
    onGameComplete(finalScore, gameTime);
  };

  // Calculate score based on moves and time
  const calculateScore = () => {
    const baseScore = 1000;
    const movesPenalty = moves * 5;
    const timePenalty = gameTime * 2;
    return Math.max(baseScore - movesPenalty - timePenalty, 100);
  };

  // Handle card click
  const handleCardClick = (id) => {
    // Ignore if already matched or more than 2 cards flipped
    if (isGameOver || matched.includes(id) || flipped.includes(id) || flipped.length >= 2) {
      return;
    }

    // Add card to flipped
    const newFlipped = [...flipped, id];
    setFlipped(newFlipped);

    // If 2 cards are flipped, check for match
    if (newFlipped.length === 2) {
      setMoves(moves + 1);
      const [firstId, secondId] = newFlipped;
      
      if (cards[firstId].icon === cards[secondId].icon) {
        // Match found
        setMatched([...matched, firstId, secondId]);
      }
      
      // Reset flipped cards after delay
      setTimeout(() => {
        setFlipped([]);
      }, 1000);
    }
  };

  // Restart game
  const restartGame = () => {
    initializeGame();
  };

  return (
    <div className="game">
      <div className="game-info">
        <p>Moves: {moves}</p>
        <p>Time: {gameTime}s</p>
        <p>Matched: {matched.length / 2} of {cards.length / 2}</p>
        {isGameOver && (
          <div className="game-over">
            <h2>Game Complete!</h2>
            <p>Score: {calculateScore()}</p>
            <p>Time: {gameTime} seconds</p>
            <p>Moves: {moves}</p>
            <button onClick={restartGame}>Play Again</button>
          </div>
        )}
      </div>

      <div className="card-grid">
        {cards.map((card) => (
          <div
            key={card.id}
            className={`card ${flipped.includes(card.id) ? 'flipped' : ''} ${matched.includes(card.id) ? 'matched' : ''}`}
            onClick={() => handleCardClick(card.id)}
          >
            <div className="card-back">?</div>
            <div className="card-front">{card.icon}</div>
          </div>
        ))}
      </div>
    </div>
  );
};

export default Game;