import { v4 as uuidv4 } from 'uuid';

interface Session {
  id: string;
  createdAt: Date;
  lastAccessedAt: Date;
  data: Record<string, any>;
}

export class SessionManager {
  private sessions: Map<string, Session> = new Map();
  private sessionTimeout: number = 30 * 60 * 1000; // 30 minutes

  constructor() {
    setInterval(() => this.cleanupExpiredSessions(), 5 * 60 * 1000);
  }

  createSession(): string {
    const sessionId = uuidv4();
    const session: Session = {
      id: sessionId,
      createdAt: new Date(),
      lastAccessedAt: new Date(),
      data: {},
    };
    this.sessions.set(sessionId, session);
    return sessionId;
  }

  getSession(sessionId: string): Session {
    let session = this.sessions.get(sessionId);
    if (!session) {
      session = {
        id: sessionId,
        createdAt: new Date(),
        lastAccessedAt: new Date(),
        data: {},
      };
      this.sessions.set(sessionId, session);
    }
    session.lastAccessedAt = new Date();
    return session;
  }

  setSessionData(sessionId: string, key: string, value: any): void {
    const session = this.getSession(sessionId);
    session.data[key] = value;
  }

  getSessionData(sessionId: string, key: string): any {
    const session = this.getSession(sessionId);
    return session.data[key];
  }

  deleteSession(sessionId: string): void {
    this.sessions.delete(sessionId);
  }

  private cleanupExpiredSessions(): void {
    const now = new Date().getTime();
    for (const [sessionId, session] of this.sessions.entries()) {
      if (now - session.lastAccessedAt.getTime() > this.sessionTimeout) {
        this.sessions.delete(sessionId);
        console.log(`Cleaned up expired session: ${sessionId}`);
      }
    }
  }

  getAllSessions(): Session[] {
    return Array.from(this.sessions.values());
  }
}