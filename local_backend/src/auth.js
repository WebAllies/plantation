const admin = require('firebase-admin');

function bearerToken(req) {
  const raw = req.headers.authorization || '';
  if (!raw.toLowerCase().startsWith('bearer ')) return '';
  return raw.slice(7).trim();
}

async function verifyToken(token) {
  if (!token) return null;
  if (!admin.apps.length) return null;
  return admin.auth().verifyIdToken(token);
}

function authMiddleware({ requireAuth }) {
  return async (req, res, next) => {
    try {
      const token = bearerToken(req);
      const decoded = token ? await verifyToken(token) : null;
      if (requireAuth && !decoded) {
        res.status(401).json({ error: 'Firebase login token required' });
        return;
      }
      req.user = decoded
        ? {
            uid: decoded.uid,
            email: decoded.email || '',
          }
        : null;
      next();
    } catch (error) {
      if (requireAuth) {
        res.status(401).json({ error: 'Invalid Firebase login token' });
        return;
      }
      req.user = null;
      next();
    }
  };
}

async function authenticateWebSocket(req, { requireAuth }) {
  const url = new URL(req.url, 'http://localhost');
  const token = url.searchParams.get('token') || '';
  const decoded = token ? await verifyToken(token) : null;
  if (requireAuth && !decoded) {
    throw new Error('Firebase login token required');
  }
  return decoded
    ? {
        uid: decoded.uid,
        email: decoded.email || '',
      }
    : null;
}

module.exports = { authMiddleware, authenticateWebSocket };
