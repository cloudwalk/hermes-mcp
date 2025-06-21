import express from 'express';
import morgan from 'morgan';
import { randomUUID } from 'node:crypto';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { isInitializeRequest } from '@modelcontextprotocol/sdk/types.js';
import { z } from 'zod';
import { SessionManager } from './session-manager.js';

const PORT = process.env.PORT || 3000;

const app = express();
app.use(morgan('dev'));
app.use(express.json());

const sessionManager = new SessionManager();

const transports: { [sessionId: string]: StreamableHTTPServerTransport } = {};

app.post('/mcp', async (req, res) => {
  const sessionId = req.headers['mcp-session-id'] as string | undefined;
  let transport: StreamableHTTPServerTransport;

  if (sessionId && transports[sessionId]) {
    transport = transports[sessionId];
  } else if (!sessionId && isInitializeRequest(req.body)) {
    transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: () => randomUUID(),
      onsessioninitialized: (sessionId) => {
        transports[sessionId] = transport;
      }
    });

    transport.onclose = () => {
      if (transport.sessionId) {
        delete transports[transport.sessionId];
        sessionManager.deleteSession(transport.sessionId);
      }
    };

    const server = new McpServer({
      name: 'session-manager-mcp',
      version: '0.1.0'
    });

    server.registerTool(
      'session_info',
      {
        title: 'Session Information',
        description: 'Get information about the current session',
        inputSchema: {}
      },
      async () => {
        const currentSessionId = transport.sessionId;
        if (!currentSessionId) {
          throw new Error('No session ID found');
        }
        
        const session = sessionManager.getSession(currentSessionId);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify({
                sessionId: currentSessionId,
                createdAt: session.createdAt,
                lastAccessedAt: session.lastAccessedAt,
                dataSize: Object.keys(session.data).length,
              }, null, 2),
            },
          ],
        };
      }
    );

    server.registerTool(
      'store_value',
      {
        title: 'Store Value',
        description: 'Store a value in the session with a given key',
        inputSchema: {
          key: z.string().describe('The key to store the value under'),
          value: z.any().describe('The value to store (can be any JSON-serializable type)')
        }
      },
      async ({ key, value }) => {
        const currentSessionId = transport.sessionId;
        if (!currentSessionId) {
          throw new Error('No session ID found');
        }
        
        sessionManager.setSessionData(currentSessionId, key, value);
        return {
          content: [
            {
              type: 'text',
              text: `Stored value for key "${key}" in session ${currentSessionId}`,
            },
          ],
        };
      }
    );

    server.registerTool(
      'get_value',
      {
        title: 'Get Value',
        description: 'Retrieve a value from the session by key',
        inputSchema: {
          key: z.string().describe('The key to retrieve the value for')
        }
      },
      async ({ key }) => {
        const currentSessionId = transport.sessionId;
        if (!currentSessionId) {
          throw new Error('No session ID found');
        }
        
        const value = sessionManager.getSessionData(currentSessionId, key);
        return {
          content: [
            {
              type: 'text',
              text: value !== undefined
                ? JSON.stringify({ key, value }, null, 2)
                : `No value found for key "${key}" in session ${currentSessionId}`,
            },
          ],
        };
      }
    );

    server.registerTool(
      'increment_counter',
      {
        title: 'Increment Counter',
        description: 'Increment a named counter in the session',
        inputSchema: {
          counterName: z.string().optional().default('default').describe('The name of the counter to increment')
        }
      },
      async ({ counterName = 'default' }) => {
        const currentSessionId = transport.sessionId;
        if (!currentSessionId) {
          throw new Error('No session ID found');
        }
        
        const currentValue = sessionManager.getSessionData(currentSessionId, `counter_${counterName}`) || 0;
        const newValue = currentValue + 1;
        sessionManager.setSessionData(currentSessionId, `counter_${counterName}`, newValue);
        return {
          content: [
            {
              type: 'text',
              text: `Counter "${counterName}" incremented to ${newValue}`,
            },
          ],
        };
      }
    );

    await server.connect(transport);
  } else {
    res.status(400).json({
      jsonrpc: '2.0',
      error: {
        code: -32000,
        message: 'Bad Request: No valid session ID provided',
      },
      id: null,
    });
    return;
  }

  await transport.handleRequest(req, res, req.body);
});

const handleSessionRequest = async (req: express.Request, res: express.Response) => {
  const sessionId = req.headers['mcp-session-id'] as string | undefined;
  if (!sessionId || !transports[sessionId]) {
    res.status(400).send('Invalid or missing session ID');
    return;
  }
  
  const transport = transports[sessionId];
  await transport.handleRequest(req, res);
};

app.get('/mcp', handleSessionRequest);

app.delete('/mcp', handleSessionRequest);

app.listen(PORT, () => {
  console.log(`Session Manager MCP server running on http://localhost:${PORT}`);
  console.log(`MCP endpoint: http://localhost:${PORT}/mcp`);
  console.log(`\nSession management is enabled. Each client gets a unique session with isolated state.`);
});