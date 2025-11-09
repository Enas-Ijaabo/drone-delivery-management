package iface

import (
	"errors"
	"sync"
	"sync/atomic"
	"time"

	"github.com/gorilla/websocket"
)

var (
	errClientClosed      = errors.New("websocket client closed")
	ErrDroneNotConnected = errors.New("drone websocket not connected")
)

type wsClient struct {
	conn     *websocket.Conn
	writeMu  sync.Mutex
	isClosed atomic.Bool
}

func newWSClient(conn *websocket.Conn) *wsClient {
	return &wsClient{conn: conn}
}

func (c *wsClient) Send(v interface{}) error {
	c.writeMu.Lock()
	defer c.writeMu.Unlock()

	if c.isClosed.Load() {
		return errClientClosed
	}

	_ = c.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
	if err := c.conn.WriteJSON(v); err != nil {
		return err
	}
	return nil
}

func (c *wsClient) Close() {
	if c.isClosed.CompareAndSwap(false, true) {
		c.writeMu.Lock()
		_ = c.conn.Close()
		c.writeMu.Unlock()
	}
}

type ConnectionRegistry struct {
	mu      sync.RWMutex
	clients map[int64]*wsClient
}

func NewConnectionRegistry() *ConnectionRegistry {
	return &ConnectionRegistry{
		clients: make(map[int64]*wsClient),
	}
}

func (r *ConnectionRegistry) Register(droneID int64, conn *websocket.Conn) *wsClient {
	client := newWSClient(conn)

	r.mu.Lock()
	if existing, ok := r.clients[droneID]; ok {
		existing.Close()
	}
	r.clients[droneID] = client
	r.mu.Unlock()

	return client
}

func (r *ConnectionRegistry) Unregister(droneID int64, client *wsClient) {
	r.mu.Lock()
	if curr, ok := r.clients[droneID]; ok && curr == client {
		delete(r.clients, droneID)
	}
	r.mu.Unlock()

	if client != nil {
		client.Close()
	}
}

func (r *ConnectionRegistry) Send(droneID int64, payload interface{}) error {
	r.mu.RLock()
	client, ok := r.clients[droneID]
	r.mu.RUnlock()

	if !ok {
		return ErrDroneNotConnected
	}

	if err := client.Send(payload); err != nil {
		r.Unregister(droneID, client)
		return err
	}
	return nil
}
