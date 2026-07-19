//line server.w:43
package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	mrand "math/rand/v2"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	bz "github.com/sjnam/bohnanza"
	"github.com/sjnam/bohnanza/bot"
)

//line server.w:76
type sub struct {
	id     int
	player int
	ch     chan []byte
}

type Game struct {
	mu         sync.Mutex
	code       string
	state      *bz.State
	subs       map[int]*sub
	nextID     int
	claimed    []bool       // |claimed[p]|가 참이면 |p|번 자리에 이미 임자가 있다
	bots       []bot.Policy // |bots[p]|가 |nil|이 아니면 |p|번 자리는 봇이다
	names      []string     // 자리마다의 표시 이름(사람은 참가 때, 봇은 만들 때 정함)
	rng        *mrand.Rand  // 봇 정책에 넘길 난수원
	chatLog    []ChatMsg    // 늦게 붙는 사람에게 되보낼 최근 채팅
	chatSeq    int          // 채팅 순번(재접속 시 중복 걸러내기용, 절대 되감지 않음)
	turnActive int          // 채팅이 매인 턴(활성 플레이어). 바뀌면 채팅을 비운다
	lastSeen   time.Time    // 마지막 활동 시각. 오래 놀고 아무도 안 보면 청소부가 치운다
}

//line server.w:103
type Message struct {
	Board  bz.View    `json:"view"`
	Events []bz.Event `json:"events"`
	Bots   []bool     `json:"bots"`  // |bots[p]|가 참이면 |p|번은 봇
	Names  []string   `json:"names"` // 자리마다의 표시 이름
}

//line server.w:115
func (g *Game) register(player int) *sub {
	g.mu.Lock()
	defer g.mu.Unlock()
	s := &sub{id: g.nextID, player: player, ch: make(chan []byte, 64)}
	g.nextID++
	g.subs[s.id] = s
	g.lastSeen = time.Now()
	s.ch <- sseFrame("", g.encode(player, nil))
	for _, m := range g.chatLog {
		data, _ := json.Marshal(m)
		s.ch <- sseFrame("chat", data)
	}
	return s
}

func (g *Game) unregister(s *sub) {
	g.mu.Lock()
	defer g.mu.Unlock()
	if _, ok := g.subs[s.id]; ok {
		delete(g.subs, s.id)
		close(s.ch)
	}
}

//line server.w:143
func (g *Game) claim() (int, bool) {
	g.mu.Lock()
	defer g.mu.Unlock()
	for p, taken := range g.claimed {
		if !taken {
			g.claimed[p] = true
			g.lastSeen = time.Now()
			return p, true
		}
	}
	return 0, false
}

func (g *Game) view(player int) bz.View {
	g.mu.Lock()
	defer g.mu.Unlock()
	return g.state.View(player)
}

//line server.w:167
func (g *Game) setName(player int, name string) {
	g.mu.Lock()
	defer g.mu.Unlock()
	name = strings.TrimSpace(strings.NewReplacer("<", "", ">", "").Replace(name))
	if name != "" {
		if r := []rune(name); len(r) > 20 {
			name = string(r[:20])
		}
		g.names[player] = name
	}
	g.broadcast(nil)
}

//line server.w:186
func (g *Game) apply(a bz.Action) ([]bz.Event, error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	events, err := g.state.Apply(a)
	if err != nil {
		return nil, err
	}
	g.lastSeen = time.Now()
	g.rolloverChat()
	g.broadcast(events)
	g.runBots()
	return events, nil
}

//line server.w:205
func (g *Game) runBots() {
	for !g.state.Over() {
		p := g.state.ToAct()
		if p < 0 || g.bots[p] == nil {
			return
		}
		ev, err := g.state.Apply(g.bots[p].Act(g.state.View(p), g.rng))
		if err != nil {
			return
		}
		g.rolloverChat()
		g.broadcast(ev)
	}
}

//line server.w:225
func (g *Game) broadcast(events []bz.Event) {
	for _, s := range g.subs {
		f := sseFrame("", g.encode(s.player, events))
		select {
		case s.ch <- f:
		default:
		}
	}
}

//line server.w:239
func sseFrame(event string, data []byte) []byte {
	if event == "" {
		return []byte("data: " + string(data) + "\n\n")
	}
	return []byte("event: " + event + "\ndata: " + string(data) + "\n\n")
}

//line server.w:250
func (g *Game) encode(player int, events []bz.Event) []byte {
	b, _ := json.Marshal(Message{Board: g.state.View(player),
		Events: events, Bots: g.botFlags(), Names: g.names})
	return b
}

func (g *Game) botFlags() []bool {
	f := make([]bool, len(g.bots))
	for i, p := range g.bots {
		f[i] = p != nil
	}
	return f
}

//line server.w:271
type session struct {
	game   *Game
	player int
}

type Hub struct {
	mu       sync.Mutex
	games    map[string]*Game   // 방 코드 $\rightarrow$ 방
	sessions map[string]session // 토큰 $\rightarrow$ 자리
}

func newHub() *Hub {
	return &Hub{games: map[string]*Game{}, sessions: map[string]session{}}
}

func (h *Hub) get(code string) *Game {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.games[code]
}

//line server.w:297
func (h *Hub) create(players, bots int, seed uint64) (string, error) {
	if bots < 0 || bots >= players {
		return "", fmt.Errorf("봇은 0명 이상 %d명 미만이어야 함", players)
	}
	st, err := bz.New(players, seed)
	if err != nil {
		return "", err
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	code := h.freshCode()
	g := &Game{code: code, state: st, subs: map[int]*sub{},
		claimed: make([]bool, players), bots: make([]bot.Policy, players),
		names: make([]string, players), lastSeen: time.Now(),
		rng: mrand.New(mrand.NewPCG(seed, seed^0x9e3779b97f4a7c15))}
	for p := range g.names {
		g.names[p] = fmt.Sprintf("%d번", p) // 사람은 참가 때 이름으로 바뀐다
	}

//line server.w:324
	for p := players - bots; p < players; p++ {
		g.bots[p] = bot.NewGreedy()
		g.claimed[p] = true
		g.names[p] = fmt.Sprintf("봇 %d", p-(players-bots)+1)
	}

//line server.w:316
	h.games[code] = g
	return code, nil
}

//line server.w:334
func (h *Hub) join(code, name string) (int, string, error) {
	g := h.get(code)
	if g == nil {
		return 0, "", fmt.Errorf("그런 방이 없음")
	}
	player, ok := g.claim()
	if !ok {
		return 0, "", fmt.Errorf("방이 가득 참")
	}
	g.setName(player, name)
	tok := randToken()
	h.mu.Lock()
	h.sessions[tok] = session{game: g, player: player}
	h.mu.Unlock()
	return player, tok, nil
}

func (h *Hub) session(tok string) (*Game, int, bool) {
	h.mu.Lock()
	defer h.mu.Unlock()
	s, ok := h.sessions[tok]
	return s.game, s.player, ok
}

//line server.w:365
const (
	roomTTL    = time.Hour        // 이만큼 놀고 아무도 안 보면 버려진 방
	sweepEvery = 10 * time.Minute // 이 간격으로 방을 훑는다
)

func (h *Hub) reap(now time.Time) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for code, g := range h.games {
		g.mu.Lock()
		if len(g.subs) == 0 && now.Sub(g.lastSeen) > roomTTL {
			delete(h.games, code)

//line server.w:387
			for tok, s := range h.sessions {
				if s.game == g {
					delete(h.sessions, tok)
				}
			}

//line server.w:378
		}
		g.mu.Unlock()
	}
}

//line server.w:396
func (h *Hub) janitor() {
	for range time.Tick(sweepEvery) {
		h.reap(time.Now())
	}
}

//line server.w:407
const codeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

func randCode() string {
	var b [4]byte
	rand.Read(b[:])
	c := make([]byte, len(b))
	for i := range c {
		c[i] = codeAlphabet[int(b[i])%len(codeAlphabet)]
	}
	return string(c)
}

func (h *Hub) freshCode() string {
	for {
		c := randCode()
		if _, taken := h.games[c]; !taken {
			return c
		}
	}
}

func randToken() string {
	var b [16]byte
	rand.Read(b[:])
	return hex.EncodeToString(b[:])
}

//line server.w:441
func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(v)
}

func (h *Hub) auth(w http.ResponseWriter, r *http.Request) (*Game, int, bool) {
	g, player, ok := h.session(requestToken(r))
	if !ok {
		http.Error(w, "토큰이 없거나 잘못됨", http.StatusUnauthorized)
	}
	return g, player, ok
}

//line server.w:458
func requestToken(r *http.Request) string {
	if h := r.Header.Get("Authorization"); strings.HasPrefix(h, "Bearer ") {
		return strings.TrimPrefix(h, "Bearer ")
	}
	if c, err := r.Cookie("bz_token"); err == nil {
		return c.Value
	}
	return ""
}

//line server.w:473
func (h *Hub) handleNew(w http.ResponseWriter, r *http.Request) {
	players, bots := 3, 0
	if v := r.URL.Query().Get("players"); v != "" {
		players, _ = strconv.Atoi(v)
	}
	if v := r.URL.Query().Get("bots"); v != "" {
		bots, _ = strconv.Atoi(v)
	}
	seed := uint64(time.Now().UnixNano())
	if v := r.URL.Query().Get("seed"); v != "" {
		if n, err := strconv.ParseUint(v, 10, 64); err == nil {
			seed = n
		}
	}
	code, err := h.create(players, bots, seed)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	writeJSON(w, map[string]any{"code": code, "players": players, "bots": bots})
}

//line server.w:500
func (h *Hub) handleJoin(w http.ResponseWriter, r *http.Request) {
	player, tok, err := h.join(r.PathValue("code"), r.URL.Query().Get("name"))
	if err != nil {
		http.Error(w, err.Error(), http.StatusConflict)
		return
	}
	writeJSON(w, map[string]any{"player": player, "token": tok})
}

//line server.w:511
func (h *Hub) handleView(w http.ResponseWriter, r *http.Request) {
	g, player, ok := h.auth(w, r)
	if !ok {
		return
	}
	writeJSON(w, g.view(player))
}

//line server.w:524
func (h *Hub) handleAction(w http.ResponseWriter, r *http.Request) {
	g, player, ok := h.auth(w, r)
	if !ok {
		return
	}
	var a bz.Action
	if err := json.NewDecoder(r.Body).Decode(&a); err != nil {
		http.Error(w, "액션 JSON을 읽을 수 없음", http.StatusBadRequest)
		return
	}
	a.Actor = player
	events, err := g.apply(a)
	if err != nil {
		http.Error(w, err.Error(), http.StatusConflict)
		return
	}
	writeJSON(w, Message{Board: g.view(player), Events: events,
		Bots: g.botFlags(), Names: g.names})
}

//line server.w:549
func (h *Hub) handleStream(w http.ResponseWriter, r *http.Request) {
	g, player, ok := h.auth(w, r)
	if !ok {
		return
	}
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "스트리밍을 지원하지 않음", http.StatusInternalServerError)
		return
	}

//line server.w:566
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")

	s := g.register(player)
	defer g.unregister(s)
	for {
		select {
		case <-r.Context().Done():
			return
		case b, ok := <-s.ch:
			if !ok {
				return
			}
			w.Write(b)
			flusher.Flush()
		}
	}

//line server.w:560
}

//line server.w:588
func handleCatalog(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, bz.Catalog())
}

//line server.w:597
type ChatMsg struct {
	Seq  int    `json:"seq"` // 방 안에서 늘 커지는 순번
	From int    `json:"from"`
	Text string `json:"text"`
}

//line server.w:608
func (g *Game) chat(from int, text string) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.chatSeq++
	g.lastSeen = time.Now()
	m := ChatMsg{Seq: g.chatSeq, From: from, Text: text}
	g.chatLog = append(g.chatLog, m)
	if len(g.chatLog) > 30 {
		g.chatLog = g.chatLog[len(g.chatLog)-30:]
	}
	data, _ := json.Marshal(m)
	for _, s := range g.subs {
		select {
		case s.ch <- sseFrame("chat", data):
		default:
		}
	}
}

//line server.w:632
func (g *Game) rolloverChat() {
	if g.state.Active != g.turnActive {
		g.turnActive = g.state.Active
		g.chatLog = nil
	}
}

//line server.w:643
func (h *Hub) handleChat(w http.ResponseWriter, r *http.Request) {
	g, player, ok := h.auth(w, r)
	if !ok {
		return
	}
	var body struct {
		Text string `json:"text"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, "채팅 JSON을 읽을 수 없음", http.StatusBadRequest)
		return
	}

//line server.w:661
	text := strings.TrimSpace(body.Text)
	if text == "" {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if rs := []rune(text); len(rs) > 300 {
		text = string(rs[:300])
	}
	g.chat(player, text)
	w.WriteHeader(http.StatusNoContent)

//line server.w:656
}

//line server.w:678
func main() {
	addr := ":8080"
	if len(os.Args) > 1 {
		addr = os.Args[1]
	}
	h := newHub()
	go h.janitor()
	mux := http.NewServeMux()
	mux.HandleFunc("POST /games", h.handleNew)
	mux.HandleFunc("POST /games/{code}/join", h.handleJoin)
	mux.HandleFunc("GET /stream", h.handleStream)
	mux.HandleFunc("POST /action", h.handleAction)
	mux.HandleFunc("POST /chat", h.handleChat)
	mux.HandleFunc("GET /view", h.handleView)
	mux.HandleFunc("GET /catalog", handleCatalog)
	log.Printf("보난자 서버 열림: %s", addr)
	log.Fatal(http.ListenAndServe(addr, mux))
}
