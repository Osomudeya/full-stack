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

// ✅ FIXED: Database connection configuration (removed duplicate import and module.exports)
const pool = new Pool({
  user: process.env.DB_USER,
  host: process.env.DB_HOST,
  database: process.env.DB_NAME,
  password: process.env.DB_PASSWORD,
  port: process.env.DB_PORT || 5432,
  ssl: {
    rejectUnauthorized: false  // Required for Azure PostgreSQL
  },
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000, // Increased timeout for Azure
});

// Add connection error handling
pool.on('error', (err, client) => {
  console.error('Unexpected error on idle client', err);
  process.exit(-1);
});

// Test database connection on startup
pool.query('SELECT NOW()', (err, res) => {
  if (err) {
    console.error('Database connection error:', err);
  } else {
    console.log('Database connected at:', res.rows[0].now);
  }
});

// ✅ IMPROVED: Health check endpoint that actually tests database
app.get('/health', async (req, res) => {
  try {
    // Test database connection
    const result = await pool.query('SELECT NOW() as server_time');
    res.status(200).json({ 
      status: 'healthy', 
      timestamp: new Date().toISOString(),
      database: 'connected',
      server_time: result.rows[0].server_time,
      environment: process.env.NODE_ENV || 'development'
    });
  } catch (error) {
    console.error('Health check failed:', error);
    res.status(503).json({ 
      status: 'unhealthy', 
      error: error.message,
      timestamp: new Date().toISOString()
    });
  }
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

// Graceful shutdown
process.on('SIGINT', async () => {
  console.log('Shutting down gracefully...');
  await pool.end();
  process.exit(0);
});

// Start the server
app.listen(port, () => {
  console.log(`Server running on port ${port}`);
  console.log(`Health check: http://localhost:${port}/health`);
  console.log(`Metrics: http://localhost:${port}/metrics`);
});