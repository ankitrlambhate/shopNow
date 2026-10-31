import React, { useState, useEffect } from 'react';
import { Search, Package, Clock, CheckCircle, XCircle, Eye, Edit, Trash2 } from 'lucide-react';

const AdminDashboard = () => {
  const [orders, setOrders] = useState([]);
  const [filteredOrders, setFilteredOrders] = useState([]);
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');
  const [selectedOrder, setSelectedOrder] = useState(null);
  const [showOrderDetails, setShowOrderDetails] = useState(false);
  const [analytics, setAnalytics] = useState({});
  const [loading, setLoading] = useState(true);

  // API base URL - replace with your backend URL
  // API base URL - from environment variable with fallback
  const API_BASE_URL = process.env.REACT_APP_API_BASE_URL || 'api';

  // Fetch orders from backend
  const fetchOrders = async () => {
    try {
      const response = await fetch(`${API_BASE_URL}/invoices`);
      const data = await response.json();
      setOrders(data.invoices || []);
      setFilteredOrders(data.invoices || []);
    } catch (error) {
      console.error('Error fetching orders:', error);
      // Fallback to sample data if API is not available
      setSampleData();
    }
  };

  // Fetch analytics
  const fetchAnalytics = async () => {
    try {
      const response = await fetch(`${API_BASE_URL}/analytics/dashboard`);
      const data = await response.json();
      setAnalytics(data);
    } catch (error) {
      console.error('Error fetching analytics:', error);
      setAnalytics({
        totalOrders: 0,
        pendingOrders: 0,
        readyOrders: 0,
        collectedOrders: 0,
        totalRevenue: 0,
        todayOrders: 0
      });
    }
  };

  // Sample data for demo purposes
  const setSampleData = () => {
    const sampleOrders = [
      {
        _id: '1',
        invoiceNumber: 'SN1695123456789',
        token: '123456',
        customerDetails: {
          name: 'John Doe',
          phone: '1234567890',
          email: 'john@example.com'
        },
        items: [
          { name: 'Wireless Headphones', price: 99.99, quantity: 1 },
          { name: 'Smart Watch', price: 249.99, quantity: 1 }
        ],
        total: 349.98,
        status: 'pending',
        paymentStatus: 'pending',
        createdAt: new Date().toISOString()
      },
      {
        _id: '2',
        invoiceNumber: 'SN1695123456790',
        token: '234567',
        customerDetails: {
          name: 'Jane Smith',
          phone: '2345678901',
          email: 'jane@example.com'
        },
        items: [
          { name: 'Coffee Maker', price: 79.99, quantity: 1 }
        ],
        total: 79.99,
        status: 'ready',
        paymentStatus: 'pending',
        createdAt: new Date().toISOString()
      }
    ];
    setOrders(sampleOrders);
    setFilteredOrders(sampleOrders);
    setAnalytics({
      totalOrders: 15,
      pendingOrders: 5,
      readyOrders: 3,
      collectedOrders: 7,
      totalRevenue: 2499.85,
      todayOrders: 4
    });
  };

  // Update order status
  const updateOrderStatus = async (orderId, newStatus) => {
    try {
      const response = await fetch(`${API_BASE_URL}/invoices/${orderId}/status`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ status: newStatus }),
      });

      if (response.ok) {
        // Update local state
        setOrders(prevOrders =>
          prevOrders.map(order =>
            order._id === orderId ? { ...order, status: newStatus } : order
          )
        );
        alert('Order status updated successfully!');
        fetchAnalytics(); // Refresh analytics
      } else {
        throw new Error('Failed to update order status');
      }
    } catch (error) {
      console.error('Error updating order status:', error);
      // Fallback for demo - update local state only
      setOrders(prevOrders =>
        prevOrders.map(order =>
          order._id === orderId ? { ...order, status: newStatus } : order
        )
      );
      alert('Order status updated (demo mode)!');
    }
  };

  // Mark order as collected using token
  const markAsCollected = async (token) => {
    try {
      const response = await fetch(`${API_BASE_URL}/invoices/token/${token}/collect`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
        },
      });

      if (response.ok) {
        fetchOrders(); // Refresh orders
        fetchAnalytics(); // Refresh analytics
        alert('Order marked as collected successfully!');
      } else {
        throw new Error('Failed to mark order as collected');
      }
    } catch (error) {
      console.error('Error marking order as collected:', error);
      // Fallback for demo
      setOrders(prevOrders =>
        prevOrders.map(order =>
          order.token === token
            ? { ...order, status: 'collected', paymentStatus: 'paid' }
            : order
        )
      );
      alert('Order marked as collected (demo mode)!');
    }
  };

  useEffect(() => {
    fetchOrders();
    fetchAnalytics();
    setLoading(false);
  }, []);

  useEffect(() => {
    let filtered = orders;

    // Filter by search term
    if (searchTerm) {
      filtered = filtered.filter(order =>
        order.invoiceNumber.toLowerCase().includes(searchTerm.toLowerCase()) ||
        order.token.includes(searchTerm) ||
        order.customerDetails.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
        order.customerDetails.phone.includes(searchTerm)
      );
    }

    // Filter by status
    if (statusFilter !== 'all') {
      filtered = filtered.filter(order => order.status === statusFilter);
    }

    setFilteredOrders(filtered);
  }, [orders, searchTerm, statusFilter]);

  const getStatusColor = (status) => {
    switch (status) {
      case 'pending': return 'text-yellow-600 bg-yellow-100';
      case 'ready': return 'text-blue-600 bg-blue-100';
      case 'collected': return 'text-green-600 bg-green-100';
      case 'cancelled': return 'text-red-600 bg-red-100';
      default: return 'text-gray-600 bg-gray-100';
    }
  };

  const getStatusIcon = (status) => {
    switch (status) {
      case 'pending': return <Clock className="h-4 w-4" />;
      case 'ready': return <Package className="h-4 w-4" />;
      case 'collected': return <CheckCircle className="h-4 w-4" />;
      case 'cancelled': return <XCircle className="h-4 w-4" />;
      default: return <Clock className="h-4 w-4" />;
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center">
        <div className="text-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600 mx-auto"></div>
          <p className="mt-4 text-gray-600">Loading dashboard...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <header className="bg-white shadow">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center py-6">
            <div>
              <h1 className="text-3xl font-bold text-gray-900">ShopNow Admin</h1>
              <p className="text-gray-600">Order Management Dashboard</p>
            </div>
            <div className="text-right">
              <p className="text-sm text-gray-600">Today's Orders</p>
              <p className="text-2xl font-bold text-blue-600">{analytics.todayOrders || 0}</p>
            </div>
          </div>
        </div>
      </header>

      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Analytics Cards */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
          <div className="bg-white overflow-hidden shadow rounded-lg">
            <div className="p-5">
              <div className="flex items-center">
                <div className="flex-shrink-0">
                  <Package className="h-6 w-6 text-gray-400" />
                </div>
                <div className="ml-5 w-0 flex-1">
                  <dl>
                    <dt className="text-sm font-medium text-gray-500 truncate">Total Orders</dt>
                    <dd className="text-lg font-medium text-gray-900">{analytics.totalOrders || 0}</dd>
                  </dl>
                </div>
              </div>
            </div>
          </div>

          <div className="bg-white overflow-hidden shadow rounded-lg">
            <div className="p-5">
              <div className="flex items-center">
                <div className="flex-shrink-0">
                  <Clock className="h-6 w-6 text-yellow-400" />
                </div>
                <div className="ml-5 w-0 flex-1">
                  <dl>
                    <dt className="text-sm font-medium text-gray-500 truncate">Pending</dt>
                    <dd className="text-lg font-medium text-gray-900">{analytics.pendingOrders || 0}</dd>
                  </dl>
                </div>
              </div>
            </div>
          </div>

          <div className="bg-white overflow-hidden shadow rounded-lg">
            <div className="p-5">
              <div className="flex items-center">
                <div className="flex-shrink-0">
                  <Package className="h-6 w-6 text-blue-400" />
                </div>
                <div className="ml-5 w-0 flex-1">
                  <dl>
                    <dt className="text-sm font-medium text-gray-500 truncate">Ready</dt>
                    <dd className="text-lg font-medium text-gray-900">{analytics.readyOrders || 0}</dd>
                  </dl>
                </div>
              </div>
            </div>
          </div>

          <div className="bg-white overflow-hidden shadow rounded-lg">
            <div className="p-5">
              <div className="flex items-center">
                <div className="flex-shrink-0">
                  <CheckCircle className="h-6 w-6 text-green-400" />
                </div>
                <div className="ml-5 w-0 flex-1">
                  <dl>
                    <dt className="text-sm font-medium text-gray-500 truncate">Total Revenue</dt>
                    <dd className="text-lg font-medium text-gray-900">${(analytics.totalRevenue || 0).toFixed(2)}</dd>
                  </dl>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Filters */}
        <div className="bg-white shadow rounded-lg mb-8">
          <div className="px-6 py-4 border-b border-gray-200">
            <h3 className="text-lg font-medium text-gray-900">Orders</h3>
          </div>
          <div className="px-6 py-4">
            <div className="flex flex-col sm:flex-row gap-4">
              <div className="flex-1">
                <div className="relative">
                  <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                    <Search className="h-5 w-5 text-gray-400" />
                  </div>
                  <input
                    type="text"
                    placeholder="Search by invoice, token, name, or phone..."
                    value={searchTerm}
                    onChange={(e) => setSearchTerm(e.target.value)}
                    className="block w-full pl-10 pr-3 py-2 border border-gray-300 rounded-md focus:ring-blue-500 focus:border-blue-500"
                  />
                </div>
              </div>
              <div>
                <select
                  value={statusFilter}
                  onChange={(e) => setStatusFilter(e.target.value)}
                  className="block w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-blue-500 focus:border-blue-500"
                >
                  <option value="all">All Status</option>
                  <option value="pending">Pending</option>
                  <option value="ready">Ready</option>
                  <option value="collected">Collected</option>
                  <option value="cancelled">Cancelled</option>
                </select>
              </div>
            </div>
          </div>
        </div>

        {/* Orders Table */}
        <div className="bg-white shadow overflow-hidden rounded-lg">
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-gray-200">
              <thead className="bg-gray-50">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Order Details
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Customer
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Total
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Status
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Date
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody className="bg-white divide-y divide-gray-200">
                {filteredOrders.map((order) => (
                  <tr key={order._id} className="hover:bg-gray-50">
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="text-sm">
                        <div className="font-medium text-gray-900">{order.invoiceNumber}</div>
                        <div className="text-gray-500">Token: {order.token}</div>
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="text-sm">
                        <div className="font-medium text-gray-900">{order.customerDetails.name}</div>
                        <div className="text-gray-500">{order.customerDetails.phone}</div>
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                      ${order.total.toFixed(2)}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${getStatusColor(order.status)}`}>
                        {getStatusIcon(order.status)}
                        <span className="ml-1 capitalize">{order.status}</span>
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      {new Date(order.createdAt).toLocaleDateString()}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium space-x-2">
                      <button
                        onClick={() => {
                          setSelectedOrder(order);
                          setShowOrderDetails(true);
                        }}
                        className="text-blue-600 hover:text-blue-900"
                      >
                        <Eye className="h-4 w-4" />
                      </button>
                      {order.status === 'pending' && (
                        <button
                          onClick={() => updateOrderStatus(order._id, 'ready')}
                          className="text-green-600 hover:text-green-900"
                        >
                          Mark Ready
                        </button>
                      )}
                      {order.status === 'ready' && (
                        <button
                          onClick={() => markAsCollected(order.token)}
                          className="text-purple-600 hover:text-purple-900"
                        >
                          Collected
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {filteredOrders.length === 0 && (
            <div className="text-center py-12">
              <Package className="h-12 w-12 text-gray-400 mx-auto mb-4" />
              <p className="text-gray-500">No orders found matching your criteria.</p>
            </div>
          )}
        </div>
      </main>

      {/* Order Details Modal */}
      {showOrderDetails && selectedOrder && (
        <div className="fixed inset-0 z-50">
          <div className="fixed inset-0 bg-black bg-opacity-50" onClick={() => setShowOrderDetails(false)} />
          <div className="fixed inset-0 flex items-center justify-center p-4">
            <div className="bg-white rounded-lg shadow-lg w-full max-w-2xl max-h-screen overflow-y-auto">
              <div className="flex items-center justify-between p-6 border-b">
                <h2 className="text-xl font-semibold">Order Details</h2>
                <button onClick={() => setShowOrderDetails(false)}>
                  <XCircle className="h-6 w-6" />
                </button>
              </div>

              <div className="p-6 space-y-6">
                {/* Order Info */}
                <div>
                  <h3 className="text-lg font-medium mb-3">Order Information</h3>
                  <div className="grid grid-cols-2 gap-4 text-sm">
                    <div>
                      <span className="font-medium">Invoice Number:</span>
                      <p>{selectedOrder.invoiceNumber}</p>
                    </div>
                    <div>
                      <span className="font-medium">Token:</span>
                      <p className="text-2xl font-bold text-red-600">{selectedOrder.token}</p>
                    </div>
                    <div>
                      <span className="font-medium">Status:</span>
                      <p className="capitalize">{selectedOrder.status}</p>
                    </div>
                    <div>
                      <span className="font-medium">Date:</span>
                      <p>{new Date(selectedOrder.createdAt).toLocaleDateString()}</p>
                    </div>
                  </div>
                </div>

                {/* Customer Info */}
                <div>
                  <h3 className="text-lg font-medium mb-3">Customer Details</h3>
                  <div className="text-sm space-y-2">
                    <p><span className="font-medium">Name:</span> {selectedOrder.customerDetails.name}</p>
                    <p><span className="font-medium">Phone:</span> {selectedOrder.customerDetails.phone}</p>
                    {selectedOrder.customerDetails.email && (
                      <p><span className="font-medium">Email:</span> {selectedOrder.customerDetails.email}</p>
                    )}
                  </div>
                </div>

                {/* Items */}
                <div>
                  <h3 className="text-lg font-medium mb-3">Items</h3>
                  <div className="space-y-3">
                    {selectedOrder.items.map((item, index) => (
                      <div key={index} className="flex justify-between items-center p-3 bg-gray-50 rounded">
                        <div>
                          <p className="font-medium">{item.name}</p>
                          <p className="text-sm text-gray-600">Quantity: {item.quantity}</p>
                        </div>
                        <div className="text-right">
                          <p className="font-medium">${(item.price * item.quantity).toFixed(2)}</p>
                          <p className="text-sm text-gray-600">${item.price} each</p>
                        </div>
                      </div>
                    ))}
                  </div>
                  <div className="mt-4 pt-4 border-t">
                    <div className="flex justify-between items-center text-lg font-bold">
                      <span>Total:</span>
                      <span>${selectedOrder.total.toFixed(2)}</span>
                    </div>
                  </div>
                </div>

                {/* Actions */}
                <div className="flex space-x-4 pt-4 border-t">
                  {selectedOrder.status === 'pending' && (
                    <button
                      onClick={() => {
                        updateOrderStatus(selectedOrder._id, 'ready');
                        setShowOrderDetails(false);
                      }}
                      className="flex-1 bg-blue-600 text-white py-2 px-4 rounded hover:bg-blue-700"
                    >
                      Mark as Ready
                    </button>
                  )}
                  {selectedOrder.status === 'ready' && (
                    <button
                      onClick={() => {
                        markAsCollected(selectedOrder.token);
                        setShowOrderDetails(false);
                      }}
                      className="flex-1 bg-green-600 text-white py-2 px-4 rounded hover:bg-green-700"
                    >
                      Mark as Collected
                    </button>
                  )}
                  <button
                    onClick={() => setShowOrderDetails(false)}
                    className="flex-1 border border-gray-300 py-2 px-4 rounded hover:bg-gray-50"
                  >
                    Close
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default AdminDashboard;