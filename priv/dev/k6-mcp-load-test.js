import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const requestDuration = new Trend('request_duration');

// Configuration via environment variables
const SERVER_TYPE = __ENV.SERVER_TYPE || 'upcase'; // 'upcase' or 'ascii'
const BASE_URL = __ENV.BASE_URL || `http://localhost:4000`;
const MCP_ENDPOINT = `${BASE_URL}/mcp`; // StreamableHTTP endpoint

// Test configuration - simple ramping test
export const options = {
  stages: [
    { duration: '10s', target: 10 },   // Warm up
    { duration: '30s', target: 50 },   // Ramp to 50 users
    { duration: '30s', target: 100 },  // Ramp to 100 users
    { duration: '30s', target: 100 },  // Hold at 100 users
    { duration: '10s', target: 0 },    // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<3000'], // 95% of requests under 3s
    errors: ['rate<0.05'],             // Less than 5% errors
  },
};

// MCP message builders
function initializeRequest(vu, iter) {
  return JSON.stringify({
    jsonrpc: '2.0',
    method: 'initialize',
    params: {
      protocolVersion: '2025-06-18',  // Latest protocol version
      clientInfo: {
        name: 'k6-load-test',
        version: '1.0.0'
      },
      capabilities: {}
    },
    id: `init_${vu || 0}_${iter || 0}`
  });
}

function toolCallRequest(toolName, args) {
  return JSON.stringify({
    jsonrpc: '2.0',
    method: 'tools/call',
    params: {
      name: toolName,
      arguments: args
    },
    id: `tool_${__VU}_${__ITER}_${Date.now()}`
  });
}

// Server-specific tool calls
function getToolCall(vuId, iteration) {
  if (SERVER_TYPE === 'upcase') {
    return toolCallRequest('upcase', {
      text: `Hello from VU ${vuId} iteration ${iteration} at ${Date.now()}`
    });
  } else {
    // ASCII server
    const fonts = ['standard', 'slant', '3d', 'banner'];
    return toolCallRequest('text_to_ascii', {
      text: `VU${vuId}`,
      font: fonts[iteration % fonts.length]
    });
  }
}

export function setup() {
  console.log(`Testing ${SERVER_TYPE} server at ${MCP_ENDPOINT}`);
  
  // Quick connectivity check
  const resp = http.post(MCP_ENDPOINT, initializeRequest(), {
    headers: { 
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
      'MCP-Protocol-Version': '2025-06-18'
    },
    timeout: '5s'
  });
  
  if (resp.status !== 200) {
    throw new Error(`Server not reachable: ${resp.status} ${resp.body}`);
  }
  
  return { startTime: Date.now() };
}

// Track session IDs per VU
const sessions = {};

export default function () {
  const vuId = __VU;
  
  // Initialize session once per VU
  if (!sessions[vuId]) {
    const initResp = http.post(
      MCP_ENDPOINT,
      initializeRequest(),
      {
        headers: { 
          'Content-Type': 'application/json',
          'Accept': 'application/json, text/event-stream',
          'MCP-Protocol-Version': '2025-06-18'
        },
        tags: { name: 'initialize' },
      }
    );
    
    const success = check(initResp, {
      'init successful': (r) => r.status === 200,
      'has session ID': (r) => r.headers['Mcp-Session-Id'] !== undefined
    });
    
    if (!success || initResp.status !== 200) {
      errorRate.add(1);
      return;
    }
    
    // Store session ID if provided
    const sessionId = initResp.headers['Mcp-Session-Id'] || `session_${vuId}`;
    sessions[vuId] = sessionId;
    allSessions[sessionId] = true; // Track globally for cleanup
    
    // Send initialized notification
    const headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
      'MCP-Protocol-Version': '2025-06-18'
    };
    
    if (sessions[vuId]) {
      headers['Mcp-Session-Id'] = sessions[vuId];
    }
    
    http.post(
      MCP_ENDPOINT,
      JSON.stringify({
        jsonrpc: '2.0',
        method: 'notifications/initialized',
        params: {}
      }),
      { headers }
    );
  }
  
  // Main test: Call the tool
  const headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json, text/event-stream',
    'MCP-Protocol-Version': '2025-06-18'
  };
  
  if (sessions[vuId]) {
    headers['Mcp-Session-Id'] = sessions[vuId];
  }
  
  const startTime = Date.now();
  const toolResp = http.post(
    MCP_ENDPOINT,
    getToolCall(vuId, __ITER),
    {
      headers,
      tags: { name: 'tool_call' },
    }
  );
  
  const duration = Date.now() - startTime;
  requestDuration.add(duration);
  
  const success = check(toolResp, {
    'tool call successful': (r) => r.status === 200,
    'response has result': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.result !== undefined;
      } catch {
        return false;
      }
    }
  });
  
  errorRate.add(!success ? 1 : 0);
  
  if (!success) {
    console.log(`Failed request: ${toolResp.status} - ${toolResp.body}`);
  }
  
  // Small pause between requests
  sleep(0.1 + Math.random() * 0.2); // 100-300ms
}

// Track all sessions globally for cleanup
const allSessions = {};

// Cleanup function to delete sessions
function cleanupSession(sessionId) {
  if (!sessionId) return;
  
  const headers = {
    'MCP-Protocol-Version': '2025-06-18',
    'Mcp-Session-Id': sessionId
  };
  
  try {
    const resp = http.del(MCP_ENDPOINT, null, { headers, timeout: '5s' });
    
    if (resp.status === 405) {
      // Server doesn't support session deletion, that's ok per spec
    } else if (resp.status === 404) {
      // Session already gone, that's fine
    } else if (resp.status >= 200 && resp.status < 300) {
      // Successfully deleted
    }
  } catch (e) {
    // Ignore cleanup errors
  }
}

export function teardown(data) {
  const duration = (Date.now() - data.startTime) / 1000;
  console.log(`\nTest completed in ${duration.toFixed(1)} seconds`);
  console.log(`Server tested: ${SERVER_TYPE}`);
  console.log(`MCP Endpoint: ${MCP_ENDPOINT}`);
  
  // Clean up all sessions
  const sessionIds = Object.keys(allSessions);
  if (sessionIds.length > 0) {
    console.log(`\nCleaning up ${sessionIds.length} sessions...`);
    
    // Batch cleanup to avoid overwhelming the server
    const batchSize = 50;
    for (let i = 0; i < sessionIds.length; i += batchSize) {
      const batch = sessionIds.slice(i, i + batchSize);
      batch.forEach(sessionId => cleanupSession(sessionId));
      
      if (i + batchSize < sessionIds.length) {
        sleep(0.1); // Small pause between batches
      }
    }
    
    console.log('Session cleanup completed');
  }
}
