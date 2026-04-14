require('dotenv').config();
const express = require('express');
const mysql = require('mysql2/promise');
const path = require('path');
const helmet = require('helmet');

const app = express();
const PORT = process.env.APP_PORT || 8080;

// ── Security & Middleware ──────────────────────
app.use(helmet());
app.use(express.json());

// ── Database Configuration ─────────────────────
const dbConfig = {
  host:               process.env.DB_HOST,
  port:               process.env.DB_PORT || 3306,
  user:               process.env.DB_USER,
  password:           process.env.DB_PASS,
  database:           process.env.DB_NAME,
  connectionLimit:    10,
  waitForConnections: true,
  connectTimeout:     10000 // 10 seconds
};

let pool;

// ── Resilient Initialization ──────────────────
async function initDB(retries = 5) {
  while (retries > 0) {
    try {
      if (!pool) pool = mysql.createPool(dbConfig);
      
      const conn = await pool.getConnection();
      console.log('Successfully connected to RDS.');
      
      await conn.execute(`
        CREATE TABLE IF NOT EXISTS todos (
          id         INT AUTO_INCREMENT PRIMARY KEY,
          title      VARCHAR(255) NOT NULL,
          completed  BOOLEAN      DEFAULT FALSE,
          created_at TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
        )
      `);
      conn.release();
      console.log('Database schema verified.');
      return; // Success
    } catch (err) {
      retries--;
      console.error(`DB Init failed. Retries left: ${retries}. Error: ${err.message}`);
      if (retries === 0) {
        console.error('Max retries reached. App will continue but DB features may fail.');
      } else {
        await new Promise(res => setTimeout(res, 5000)); // Wait 5s before retry
      }
    }
  }
}

// ── SHALLOW Health Check ──────────────────────
// CRITICAL: This must return 200 even if the DB is still connecting
// to stop the ASG from killing the instance.
app.get('/health', (req, res) => {
  res.status(200).send('OK');
});

// ── API Routes (Example) ──────────────────────
app.get('/api/todos', async (req, res) => {
  if (!pool) return res.status(503).json({ error: 'Database initializing' });
  try {
    const [rows] = await pool.execute('SELECT * FROM todos ORDER BY created_at DESC');
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: 'Database query failed' });
  }
});

// ── Static Assets ─────────────────────────────
app.use(express.static(path.join(__dirname, 'public')));
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// ── Non-Blocking Start ────────────────────────
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server listening on port ${PORT}`);
  // Start DB init in the background
  initDB();
});

// Graceful shutdown
process.on('SIGTERM', async () => {
  if (pool) await pool.end();
  process.exit(0);
});