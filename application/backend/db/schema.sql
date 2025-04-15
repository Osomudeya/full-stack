-- Create the scores table
CREATE TABLE IF NOT EXISTS scores (
  id SERIAL PRIMARY KEY,
  player_name VARCHAR(100) NOT NULL,
  score INTEGER NOT NULL,
  time INTEGER,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create an index for faster querying
CREATE INDEX IF NOT EXISTS idx_scores_score ON scores(score DESC);

-- Insert some initial data
INSERT INTO scores (player_name, score, time)
VALUES 
  ('Player1', 100, 60),
  ('Player2', 90, 70),
  ('Player3', 85, 75)
ON CONFLICT DO NOTHING;