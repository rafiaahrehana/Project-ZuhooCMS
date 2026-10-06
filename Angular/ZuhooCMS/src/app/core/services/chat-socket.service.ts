import { Injectable } from '@angular/core';
import { Client, IMessage, StompSubscription } from '@stomp/stompjs';
import { environment } from '../../../environments/environment';
import { AuthService } from './auth.service';

/** `/ws` carries service-request comments and CUSTOMER_SUPPORT chat; `/ws/support` carries PLATFORM_SUPPORT ticket chat. */
export type ChatSocketEndpoint = '/ws' | '/ws/support';

interface SocketEntry {
  destination: string;
  handler: (payload: any) => void;
}

/** One STOMP connection to one endpoint, with its own pending/active subscriptions. */
interface SocketConnection {
  client: Client;
  pending: SocketEntry[];
  /**
   * Keyed by the entry, not the destination: two components on the same destination (a list and a detail
   * pane on the same request, or the same page opened twice in one session) each need their own STOMP
   * subscription. Keyed by destination, the second subscriber silently received no frames and whichever
   * one unsubscribed first tore down the subscription the other was still using.
   */
  activeSubs: Map<SocketEntry, StompSubscription>;
  connected: boolean;
}

/**
 * One lazily-opened persistent WebSocket per endpoint for the whole session, shared by every chat surface.
 * Messages are addressed per-user (convertAndSendToUser), never a public /topic - see ServiceRequestServiceImpl.pushChatMessage / SupportMessageServiceImpl.pushChatMessage.
 * Plain WebSocket, no SockJS: matches backend WebSocketConfig and avoids sockjs-client's `global` reference, which esbuild/Vite does not polyfill.
 * The JWT rides in ?token= because native WebSocket cannot send an Authorization header; WebSocketAuthInterceptor validates it at the handshake.
 */
@Injectable({ providedIn: 'root' })
export class ChatSocketService {
  private connections = new Map<ChatSocketEndpoint, SocketConnection>();

  constructor(private auth: AuthService) {}

  /** Whether the default `/ws` connection is up. */
  get connected(): boolean {
    return this.isConnected('/ws');
  }

  isConnected(endpoint: ChatSocketEndpoint = '/ws'): boolean {
    return this.connections.get(endpoint)?.connected ?? false;
  }

  /** Subscribes to a per-user destination (e.g. /user/queue/service-requests/13/messages); returns an unsubscribe fn. */
  subscribe(destination: string, handler: (payload: any) => void, endpoint: ChatSocketEndpoint = '/ws'): () => void {
    const entry: SocketEntry = { destination, handler };
    const conn = this.ensureConnection(endpoint);
    conn.pending.push(entry);

    if (conn.client.connected) {
      this.doSubscribe(conn, entry);
    }

    return () => {
      conn.pending = conn.pending.filter((p) => p !== entry);
      conn.activeSubs.get(entry)?.unsubscribe();
      conn.activeSubs.delete(entry);
    };
  }

  private ensureConnection(endpoint: ChatSocketEndpoint): SocketConnection {
    const existing = this.connections.get(endpoint);
    if (existing) return existing;

    // environment.apiUrl already ends in "/api" - the WS endpoint is a sibling of it.
    const wsBaseUrl = environment.apiUrl.replace(/\/api\/?$/, '').replace(/^http/, 'ws');

    const conn: SocketConnection = {
      client: null as unknown as Client,
      pending: [],
      activeSubs: new Map<SocketEntry, StompSubscription>(),
      connected: false,
    };
    conn.client = new Client({
      // webSocketFactory, not brokerURL: brokerURL is read once when the Client is constructed, so the
      // 5-second reconnect kept replaying the token this session started with. After a refresh that token
      // is expired, WebSocketAuthInterceptor rejects the handshake every time, and chat stopped reconnecting
      // for the rest of the session with no error anywhere. The factory runs on every attempt, so each one
      // carries the token that is current then.
      webSocketFactory: () => new WebSocket(
        `${wsBaseUrl}${endpoint}?token=${encodeURIComponent(this.auth.getAccessToken() || '')}`),
      reconnectDelay: 5000,
      onConnect: () => {
        conn.connected = true;
        // (Re)subscribe everything: this fires on the first connect and on every reconnect.
        conn.pending.forEach((entry) => this.doSubscribe(conn, entry));
      },
      onWebSocketClose: () => {
        conn.connected = false;
        conn.activeSubs.clear();
      },
    });
    this.connections.set(endpoint, conn);
    conn.client.activate();
    return conn;
  }

  private doSubscribe(conn: SocketConnection, entry: SocketEntry): void {
    if (!conn.client.connected || conn.activeSubs.has(entry)) return;
    const sub = conn.client.subscribe(entry.destination, (frame: IMessage) => {
      try {
        entry.handler(JSON.parse(frame.body));
      } catch {
        // ignore malformed frame
      }
    });
    conn.activeSubs.set(entry, sub);
  }
}
