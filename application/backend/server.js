const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');
const promClient = require('prom-client');
const morgan = require('morgan');

// Create a Prometheus registry
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });

// Create custom metrics
const httpRequestDurationMicroseconds = new promClient.Histogram({
  name: 'http_request_duration_ms',
  help: 'Duration of HTTP requests in ms',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [1, 5, 15, 50, 100, 200, 500, 1000, 2000]
});

const httpRequestCounter = new promClient.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code']
});

register.registerMetric(httpRequestDurationMicroseconds);
register.registerMetric(httpRequestCounter);

const app = express();
const port = process.env.PORT || 3001;

// Middleware
app.use(cors());
app.use(express.json());
app.use(morgan('combined'));

// Middleware to track request duration and count
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = Date.now() - start;
    httpRequestDurationMicroseconds
      .labels(req.method, req.path, res.statusCode)
      .observe(duration);
    httpRequestCounter
      .labels(req.method, req.path, res.statusCode)
      .inc();
  });
  next();
});

// Database connection
const pool = new Pool({
  user: process.env.DB_USER || 'postgres',
  host: process.env.DB_HOST || 'postgres',
  database: process.env.DB_NAME || 'gamedb',
  password: process.env.DB_PASSWORD || 'd2h5bm90Z29nZXRhbGlmZS15b3UtZm9vb29vb2w=',
  port: process.env.DB_PORT || 5432,
});

// Test database connection
pool.query('SELECT NOW()', (err, res) => {
  if (err) {
    console.error('Database connection error:', err);
  } else {
    console.log('Database connected at:', res.rows[0].now);
  }
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

// Metrics endpoint for Prometheus
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// API Routes
app.get('/api/scores', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM scores ORDER BY score DESC LIMIT 10'
    );
    res.json(result.rows);
  } catch (err) {
    console.error('Error fetching scores:', err);
    res.status(500).json({ error: 'Failed to fetch scores' });
  }
});

app.post('/api/scores', async (req, res) => {
  const { playerName, score, time } = req.body;
  
  if (!playerName || score === undefined) {
    return res.status(400).json({ error: 'Player name and score are required' });
  }
  
  try {
    const result = await pool.query(
      'INSERT INTO scores(player_name, score, time) VALUES($1, $2, $3) RETURNING *',
      [playerName, score, time]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error('Error saving score:', err);
    res.status(500).json({ error: 'Failed to save score' });
  }
});

// Start the server
app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});