// server.js
const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const dotenv = require('dotenv');
const path = require('path');
const client = require('prom-client');

// Load environment variables
dotenv.config();

const app = express();
const PORT = process.env.PORT || 5000;

// Middleware - CORS configuration AFTER app is created
app.use(cors({
  origin: ['http://localhost:3000', 'http://localhost:3001'],
  methods: ['GET', 'POST', 'PUT', 'DELETE'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true
}));

app.use(express.json());
app.use(express.static('public'));

// Prometheus metrics (scraped by the monitoring stack through a ServiceMonitor)
const metricsRegistry = new client.Registry();
client.collectDefaultMetrics({ register: metricsRegistry });

const httpRequestsTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total HTTP requests',
  labelNames: ['method', 'route', 'status'],
  registers: [metricsRegistry],
});

const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration in seconds',
  labelNames: ['method', 'route', 'status'],
  buckets: [0.005, 0.01, 0.05, 0.1, 0.5, 1, 2, 5],
  registers: [metricsRegistry],
});

app.use((req, res, next) => {
  const stopTimer = httpRequestDuration.startTimer();
  res.on('finish', () => {
    // Use the route pattern (e.g. /api/products/:id), not the raw path, to keep label cardinality low
    const route = req.route ? req.route.path : 'unmatched';
    const labels = { method: req.method, route, status: res.statusCode };
    httpRequestsTotal.inc(labels);
    stopTimer(labels);
  });
  next();
});

// MongoDB Connection
mongoose.connect(process.env.MONGODB_URI || 'mongodb://localhost:27017/shopnow', {
  useNewUrlParser: true,
  useUnifiedTopology: true,
})
.then(() => console.log('MongoDB connected successfully'))
.catch(err => console.error('MongoDB connection error:', err));


// MongoDB Schemas
const productSchema = new mongoose.Schema({
  name: { type: String, required: true },
  price: { type: Number, required: true },
  category: { type: String, required: true },
  image: { type: String, required: true },
  description: { type: String, required: true },
  rating: { type: Number, default: 0 },
  stock: { type: Number, required: true },
  createdAt: { type: Date, default: Date.now }
});

const invoiceSchema = new mongoose.Schema({
  invoiceNumber: { type: String, required: true, unique: true },
  token: { type: String, required: true, unique: true },
  customerDetails: {
    name: { type: String, required: true },
    phone: { type: String, required: true },
    email: { type: String }
  },
  items: [{
    _id: String,
    name: String,
    price: Number,
    quantity: Number,
    image: String
  }],
  total: { type: Number, required: true },
  status: { 
    type: String, 
    enum: ['pending', 'ready', 'collected', 'cancelled'],
    default: 'pending'
  },
  paymentMethod: { type: String, default: 'Cash on Delivery' },
  paymentStatus: {
    type: String,
    enum: ['pending', 'paid'],
    default: 'pending'
  },
  createdAt: { type: Date, default: Date.now },
  collectedAt: { type: Date }
});

const userSchema = new mongoose.Schema({
  name: { type: String, required: true },
  email: { type: String, required: true, unique: true },
  phone: { type: String, required: true },
  orders: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Invoice' }],
  createdAt: { type: Date, default: Date.now }
});

// Models
const Product = mongoose.model('Product', productSchema);
const Invoice = mongoose.model('Invoice', invoiceSchema);
const User = mongoose.model('User', userSchema);

mongoose.connection.once('open', async () => {
  try {
    const productCount = await Product.countDocuments();
    if (productCount === 0) {
      console.log('No products found, seeding database...');
      const sampleProducts = [
        {
          name: 'Wireless Headphones',
          price: 99.99,
          category: 'electronics',
          image: 'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?w=300&h=300&fit=crop&crop=center',
          description: 'High-quality wireless headphones with noise cancellation',
          rating: 4.5,
          stock: 50
        },
        {
          name: 'Smart Watch',
          price: 249.99,
          category: 'electronics',
          image: 'https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=300&h=300&fit=crop&crop=center',
          description: 'Advanced smartwatch with health monitoring features',
          rating: 4.3,
          stock: 30
        },
        {
          name: 'Coffee Maker',
          price: 79.99,
          category: 'home',
          image: 'https://images.unsplash.com/photo-1559056199-641a0ac8b55e?w=300&h=300&fit=crop&crop=center',
          description: 'Automatic drip coffee maker with programmable timer',
          rating: 4.7,
          stock: 25
        },
        {
          name: 'Running Shoes',
          price: 129.99,
          category: 'fashion',
          image: 'https://images.unsplash.com/photo-1542291026-7eec264c27ff?w=300&h=300&fit=crop&crop=center',
          description: 'Comfortable running shoes with advanced cushioning',
          rating: 4.4,
          stock: 40
        },
        {
          name: 'Laptop Stand',
          price: 45.99,
          category: 'electronics',
          image: 'https://images.unsplash.com/photo-1527864550417-7fd91fc51a46?w=300&h=300&fit=crop&crop=center',
          description: 'Ergonomic adjustable laptop stand for better posture',
          rating: 4.2,
          stock: 60
        },
        {
          name: 'Organic Cotton T-Shirt',
          price: 29.99,
          category: 'fashion',
          image: 'https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?w=300&h=300&fit=crop&crop=center',
          description: 'Soft organic cotton t-shirt in various colors',
          rating: 4.6,
          stock: 100
        }
      ];
      await Product.insertMany(sampleProducts);
      console.log('Database seeded with sample products');
    } else {
      console.log(`Database already has ${productCount} products`);
    }
  } catch (error) {
    console.error('Error during auto-seed:', error.message);
  }
});

// Utility Functions
const generateInvoiceNumber = () => {
  const timestamp = Date.now();
  const random = Math.floor(Math.random() * 1000);
  return `SN${timestamp}${random}`;
};

const generateToken = () => {
  return Math.floor(Math.random() * 900000) + 100000; // 6-digit token
};

// API Routes

// Health Check
app.get('/', (req, res) => {
  res.json({ status: 'OK', message: 'check /api/health' });
});

app.get('/api/health', (req, res) => {
  res.json({ status: 'OK', message: 'ShopNow API is running' });
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', metricsRegistry.contentType);
  res.end(await metricsRegistry.metrics());
});

// Products Routes
app.get('/api/products', async (req, res) => {
  try {
    const { category, search, page = 1, limit = 20 } = req.query;
    let query = {};
    
    // Category filter
    if (category && category !== 'all') {
      query.category = category;
    }
    
    // Search filter
    if (search) {
      query.$or = [
        { name: { $regex: search, $options: 'i' } },
        { description: { $regex: search, $options: 'i' } }
      ];
    }
    
    const products = await Product.find(query)
      .limit(limit * 1)
      .skip((page - 1) * limit)
      .sort({ createdAt: -1 });
    
    const total = await Product.countDocuments(query);
    
    res.json({
      products,
      totalPages: Math.ceil(total / limit),
      currentPage: page,
      total
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/products/:id', async (req, res) => {
  try {
    const product = await Product.findById(req.params.id);
    if (!product) {
      return res.status(404).json({ error: 'Product not found' });
    }
    res.json(product);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.post('/api/products', async (req, res) => {
  try {
    const product = new Product(req.body);
    await product.save();
    res.status(201).json(product);
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
});

app.put('/api/products/:id', async (req, res) => {
  try {
    const product = await Product.findByIdAndUpdate(
      req.params.id,
      req.body,
      { new: true, runValidators: true }
    );
    if (!product) {
      return res.status(404).json({ error: 'Product not found' });
    }
    res.json(product);
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
});

app.delete('/api/products/:id', async (req, res) => {
  try {
    const product = await Product.findByIdAndDelete(req.params.id);
    if (!product) {
      return res.status(404).json({ error: 'Product not found' });
    }
    res.json({ message: 'Product deleted successfully' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Invoice Routes
app.post('/api/invoices', async (req, res) => {
  try {
    const { customerDetails, items, total } = req.body;
    
    // Validate required fields
    if (!customerDetails.name || !customerDetails.phone || !items || !total) {
      return res.status(400).json({ 
        error: 'Missing required fields: customerDetails.name, customerDetails.phone, items, total' 
      });
    }
    
    // Generate unique invoice number and token
    let invoiceNumber, token;
    let isUnique = false;
    
    while (!isUnique) {
      invoiceNumber = generateInvoiceNumber();
      token = generateToken().toString();
      
      const existingInvoice = await Invoice.findOne({
        $or: [{ invoiceNumber }, { token }]
      });
      
      if (!existingInvoice) {
        isUnique = true;
      }
    }
    
    // Create invoice
    const invoice = new Invoice({
      invoiceNumber,
      token,
      customerDetails,
      items,
      total,
      status: 'pending',
      paymentMethod: 'Cash on Delivery',
      paymentStatus: 'pending'
    });
    
    await invoice.save();
    
    // Update product stock
    for (const item of items) {
      await Product.findByIdAndUpdate(
        item._id,
        { $inc: { stock: -item.quantity } }
      );
    }
    
    res.status(201).json({
      success: true,
      invoice,
      message: 'Invoice created successfully'
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/invoices', async (req, res) => {
  try {
    const { 
      status, 
      paymentStatus, 
      token, 
      invoiceNumber, 
      page = 1, 
      limit = 20 
    } = req.query;
    
    let query = {};
    
    if (status) query.status = status;
    if (paymentStatus) query.paymentStatus = paymentStatus;
    if (token) query.token = token;
    if (invoiceNumber) query.invoiceNumber = invoiceNumber;
    
    const invoices = await Invoice.find(query)
      .limit(limit * 1)
      .skip((page - 1) * limit)
      .sort({ createdAt: -1 });
    
    const total = await Invoice.countDocuments(query);
    
    res.json({
      invoices,
      totalPages: Math.ceil(total / limit),
      currentPage: page,
      total
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/invoices/:id', async (req, res) => {
  try {
    const invoice = await Invoice.findById(req.params.id);
    if (!invoice) {
      return res.status(404).json({ error: 'Invoice not found' });
    }
    res.json(invoice);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/invoices/token/:token', async (req, res) => {
  try {
    const invoice = await Invoice.findOne({ token: req.params.token });
    if (!invoice) {
      return res.status(404).json({ error: 'Invoice not found with this token' });
    }
    res.json(invoice);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.put('/api/invoices/:id/status', async (req, res) => {
  try {
    const { status, paymentStatus } = req.body;
    const updateData = {};
    
    if (status) updateData.status = status;
    if (paymentStatus) updateData.paymentStatus = paymentStatus;
    
    // If status is being changed to 'collected', set collectedAt timestamp
    if (status === 'collected') {
      updateData.collectedAt = new Date();
    }
    
    const invoice = await Invoice.findByIdAndUpdate(
      req.params.id,
      updateData,
      { new: true, runValidators: true }
    );
    
    if (!invoice) {
      return res.status(404).json({ error: 'Invoice not found' });
    }
    
    res.json({
      success: true,
      invoice,
      message: 'Invoice status updated successfully'
    });
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
});

app.put('/api/invoices/token/:token/collect', async (req, res) => {
  try {
    const invoice = await Invoice.findOneAndUpdate(
      { token: req.params.token },
      {
        status: 'collected',
        paymentStatus: 'paid',
        collectedAt: new Date()
      },
      { new: true, runValidators: true }
    );
    
    if (!invoice) {
      return res.status(404).json({ error: 'Invoice not found with this token' });
    }
    
    res.json({
      success: true,
      invoice,
      message: 'Package collected successfully'
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// User Routes
app.post('/api/users', async (req, res) => {
  try {
    const user = new User(req.body);
    await user.save();
    res.status(201).json(user);
  } catch (error) {
    if (error.code === 11000) {
      return res.status(400).json({ error: 'User with this email already exists' });
    }
    res.status(400).json({ error: error.message });
  }
});

app.get('/api/users/:email/orders', async (req, res) => {
  try {
    const invoices = await Invoice.find({
      'customerDetails.email': req.params.email
    }).sort({ createdAt: -1 });
    
    res.json(invoices);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Analytics Routes
app.get('/api/analytics/dashboard', async (req, res) => {
  try {
    const [
      totalOrders,
      pendingOrders,
      readyOrders,
      collectedOrders,
      totalRevenue,
      todayOrders
    ] = await Promise.all([
      Invoice.countDocuments(),
      Invoice.countDocuments({ status: 'pending' }),
      Invoice.countDocuments({ status: 'ready' }),
      Invoice.countDocuments({ status: 'collected' }),
      Invoice.aggregate([
        { $match: { status: 'collected' } },
        { $group: { _id: null, total: { $sum: '$total' } } }
      ]),
      Invoice.countDocuments({
        createdAt: {
          $gte: new Date(new Date().setHours(0, 0, 0, 0))
        }
      })
    ]);
    
    res.json({
      totalOrders,
      pendingOrders,
      readyOrders,
      collectedOrders,
      totalRevenue: totalRevenue[0]?.total || 0,
      todayOrders
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Categories Route
app.get('/api/categories', async (req, res) => {
  try {
    const categories = await Product.distinct('category');
    res.json(categories);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Seed Products Route (for development)
app.post('/api/seed/products', async (req, res) => {
  try {
    // Clear existing products
    await Product.deleteMany({});
    
    const sampleProducts = [
      {
        name: 'Wireless Headphones',
        price: 99.99,
        category: 'electronics',
        image: 'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?w=300&h=300&fit=crop&crop=center',
        description: 'High-quality wireless headphones with noise cancellation',
        rating: 4.5,
        stock: 50
      },
      {
        name: 'Smart Watch',
        price: 249.99,
        category: 'electronics',
        image: 'https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=300&h=300&fit=crop&crop=center',
        description: 'Advanced smartwatch with health monitoring features',
        rating: 4.3,
        stock: 30
      },
      {
        name: 'Coffee Maker',
        price: 79.99,
        category: 'home',
        image: 'https://images.unsplash.com/photo-1559056199-641a0ac8b55e?w=300&h=300&fit=crop&crop=center',
        description: 'Automatic drip coffee maker with programmable timer',
        rating: 4.7,
        stock: 25
      },
      {
        name: 'Running Shoes',
        price: 129.99,
        category: 'fashion',
        image: 'https://images.unsplash.com/photo-1542291026-7eec264c27ff?w=300&h=300&fit=crop&crop=center',
        description: 'Comfortable running shoes with advanced cushioning',
        rating: 4.4,
        stock: 40
      },
      {
        name: 'Laptop Stand',
        price: 45.99,
        category: 'electronics',
        image: 'https://images.unsplash.com/photo-1527864550417-7fd91fc51a46?w=300&h=300&fit=crop&crop=center',
        description: 'Ergonomic adjustable laptop stand for better posture',
        rating: 4.2,
        stock: 60
      },
      {
        name: 'Organic Cotton T-Shirt',
        price: 29.99,
        category: 'fashion',
        image: 'https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?w=300&h=300&fit=crop&crop=center',
        description: 'Soft organic cotton t-shirt in various colors',
        rating: 4.6,
        stock: 100
      }
    ];
    
    await Product.insertMany(sampleProducts);
    res.json({ message: 'Products seeded successfully', count: sampleProducts.length });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ error: 'Something went wrong!' });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'Route not found' });
});

// Start server only when run directly (so tests can import the app without opening a port)
if (require.main === module) {
  const server = app.listen(PORT, () => {
    console.log(`ShopNow API server running on port ${PORT}`);
    console.log(`Health check: http://localhost:${PORT}/api/health`);
  });

  // Graceful shutdown so Kubernetes rolling updates do not drop in-flight requests
  process.on('SIGTERM', () => {
    console.log('SIGTERM received, shutting down');
    server.close(() => mongoose.connection.close(false).finally(() => process.exit(0)));
  });
}

module.exports = app;