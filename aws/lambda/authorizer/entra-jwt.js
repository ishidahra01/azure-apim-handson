const jwt = require('jsonwebtoken');
const jwksClient = require('jwks-rsa');

// JWKS クライアントの設定
const client = jwksClient({
  jwksUri: `https://login.microsoftonline.com/${process.env.TENANT_ID}/discovery/v2.0/keys`,
  cache: true,
  cacheMaxAge: 86400000, // 24時間
  rateLimit: true,
  jwksRequestsPerMinute: 10
});

/**
 * JWKS から公開鍵を取得
 */
function getKey(header, callback) {
  client.getSigningKey(header.kid, (err, key) => {
    if (err) {
      console.error('Failed to get signing key:', err);
      callback(err);
    } else {
      const signingKey = key.getPublicKey();
      callback(null, signingKey);
    }
  });
}

/**
 * Lambda Authorizer ハンドラー（Entra ID JWT検証）
 * 
 * HTTP API の REQUEST タイプ authorizer
 */
exports.handler = async (event) => {
  console.log('Authorizer invoked:', JSON.stringify(event, null, 2));
  
  // Authorization ヘッダーからトークンを取得
  const authHeader = event.headers?.authorization || event.headers?.Authorization;
  
  if (!authHeader) {
    console.error('No Authorization header');
    return {
      isAuthorized: false
    };
  }
  
  const token = authHeader.replace('Bearer ', '');
  
  if (!token) {
    console.error('No token in Authorization header');
    return {
      isAuthorized: false
    };
  }
  
  // JWT 検証
  return new Promise((resolve, reject) => {
    jwt.verify(token, getKey, {
      audience: process.env.AUDIENCE,
      issuer: `https://login.microsoftonline.com/${process.env.TENANT_ID}/v2.0`,
      algorithms: ['RS256']
    }, (err, decoded) => {
      if (err) {
        console.error('JWT verification failed:', err.message);
        resolve({
          isAuthorized: false
        });
      } else {
        console.log('JWT verified successfully:', decoded);
        
        // スコープチェック
        const scopes = decoded.scp ? decoded.scp.split(' ') : [];
        const hasRequiredScope = scopes.some(scope => 
          scope === 'Orders.Read' || scope === 'Orders.ReadWrite'
        );
        
        if (!hasRequiredScope) {
          console.error('Missing required scope');
          resolve({
            isAuthorized: false
          });
          return;
        }
        
        // クレームを context に設定（Integration Request でヘッダーにマッピング可能）
        resolve({
          isAuthorized: true,
          context: {
            callerId: decoded.oid || 'unknown',
            callerEmail: decoded.email || decoded.upn || 'unknown',
            scopes: scopes.join(','),
            tenantId: decoded.tid || 'unknown'
          }
        });
      }
    });
  });
};
