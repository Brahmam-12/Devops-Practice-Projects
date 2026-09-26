const express = require('express')
const { Pool } = require('pg')

const app = express()
app.use(express.json())

const pool = new Pool({
  host:     process.env.DB_HOST     || 'localhost',
  port:     parseInt(process.env.DB_PORT) || 5432,
  database: process.env.DB_NAME     || 'productsdb',
  user:     process.env.DB_USER     || 'postgres',
  password: process.env.DB_PASSWORD || 'postgres123',
})

async function initDB() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS products (
      id         SERIAL PRIMARY KEY,
      name       VARCHAR(200) NOT NULL,
      price      NUMERIC(10,2) NOT NULL CHECK (price >= 0),
      stock      INTEGER DEFAULT 0 CHECK (stock >= 0),
      created_at TIMESTAMP DEFAULT NOW()
    )
  `)
  console.log('[product-service] products table ready')
}

// ── Routes ───────────────────────────────────────────────────────────────────

app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'product-service', timestamp: new Date() })
})

app.get('/products', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM products ORDER BY id')
    res.json(result.rows)
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: err.message })
  }
})

app.post('/products', async (req, res) => {
  const { name, price, stock } = req.body
  if (!name || price === undefined) {
    return res.status(400).json({ error: 'name and price are required' })
  }
  try {
    const result = await pool.query(
      'INSERT INTO products (name, price, stock) VALUES ($1, $2, $3) RETURNING *',
      [name, parseFloat(price), parseInt(stock) || 0]
    )
    res.status(201).json(result.rows[0])
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: err.message })
  }
})

app.get('/products/:id', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM products WHERE id = $1',
      [req.params.id]
    )
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'product not found' })
    }
    res.json(result.rows[0])
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: err.message })
  }
})

app.patch('/products/:id/stock', async (req, res) => {
  const { stock } = req.body
  if (stock === undefined) {
    return res.status(400).json({ error: 'stock is required' })
  }
  try {
    const result = await pool.query(
      'UPDATE products SET stock = $1 WHERE id = $2 RETURNING *',
      [parseInt(stock), req.params.id]
    )
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'product not found' })
    }
    res.json(result.rows[0])
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: err.message })
  }
})

app.delete('/products/:id', async (req, res) => {
  try {
    const result = await pool.query(
      'DELETE FROM products WHERE id = $1 RETURNING *',
      [req.params.id]
    )
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'product not found' })
    }
    res.json({ deleted: result.rows[0] })
  } catch (err) {
    console.error(err)
    res.status(500).json({ error: err.message })
  }
})

// ── Start ────────────────────────────────────────────────────────────────────

const PORT = process.env.PORT || 3001

initDB()
  .then(() => {
    app.listen(PORT, () => {
      console.log(`[product-service] listening on port ${PORT}`)
    })
  })
  .catch(err => {
    console.error('[product-service] failed to connect to DB:', err.message)
    process.exit(1)
  })
