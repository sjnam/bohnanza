@i ../types.w

\input kotexgweb

\datethis
\def\title{보난자 서버}

@* 들어가며.
이 프로그램은 보난자 게임 엔진(\.{bohnanza}) 위에 얹는 HTTP 서버다. 권위 있는
게임 상태는 서버가 쥐고, 접속한 플레이어마다 {\it 자기 시점의 뷰\/}만 실시간으로
흘려보낸다. 남의 손패나 덱 속은 서버 밖으로 나가지 않는다---엔진의 |View|가
이미 그 경계를 긋고 있으니, 서버는 그것을 실어 나르기만 하면 된다.

밀어내기(server push)는 SSE(Server-Sent Events)로 한다. 표준 라이브러리
|net/http|만으로 서버$\to$클라이언트 실시간 전송이 되고, 클라이언트$\to$서버는
평범한 POST로 충분하다. 외부 의존성이 없어 어디서나 곧장 돈다.

@ API는 일곱 갈래다. 게임을 만들고, 방에 참가해 자리와 토큰을 받고, 자기 뷰를
스트림으로 구독하고, 수를 보내고, 채팅하고, 필요하면 뷰를 한 번 찍어 오고, 콩
도감을 받는다. 정적 웹 클라이언트(\.{web/index.html})는 서버가 아니라 앞단의
nginx가 내보낸다---서버는 게임 API에만 집중한다.

$$\vbox{\halign{\indent\tt#\hfil&\quad#\hfil\cr
POST /games&                 새 게임(인원\slash 봇수\slash 씨앗) $\to$ 방 코드\cr
POST /games/:code/join&      빈자리 잡기 $\to$ 자리 번호 + 토큰\cr
GET /stream&                 내 뷰를 SSE로 구독\cr
POST /action&                액션(JSON)을 보냄\cr
POST /chat&                  방에 채팅 한 줄 보냄\cr
GET /view&                   내 뷰를 한 번 받음\cr
GET /catalog&                콩 도감(고정 정보)\cr}}$$

\noindent
{\bf 방 코드\/}는 사람이 부르기 쉬운 짧은 코드고, {\bf 토큰\/}은 참가할 때 자리마다
발급하는 비밀 열쇠다. 스트림\slash 액션\slash 뷰는 이 토큰으로 신원을 확인하므로,
남의 자리로 수를 두는 것이 원천 봉쇄된다. 토큰은 URL에 싣지 않는다---%
액션\slash 뷰는 |Authorization: Bearer| 머리글로, 스트림은 쿠키로 실어 보낸다(SSE의
|EventSource|가 머리글을 못 실어서다). 클라이언트는 토큰을 간직했다가 새로고침
뒤에도 그대로 써서 같은 자리로 다시 붙는다.

@ 프로그램은 한 \GO/ 패키지 |main|으로 나온다. |Hub|가 여러 게임 방을 관리하고,
각 방은 자기 뮤텍스로 상태를 지킨다. 아래 조각들이 위에서 아래로 쌓인다.
@c
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

@<게임 방과 구독자@>@;
@<수를 적용하고 알리기@>@;
@<게임 관리소@>@;
@<HTTP 손잡이@>@;
@<채팅@>@;
@<문 열기@>@;

@* 게임 방과 구독자.
게임 방 |Game|은 엔진 상태 하나와, 그 판을 지켜보는 구독자들의 목록을 쥔다.
엔진 상태는 여러 손이 동시에 만지면 안 되므로, 방마다 뮤텍스로 모든 접근을
한 줄로 세운다. 구독자 |sub|은 한 SSE 접속이다: 어느 플레이어의 시점인지와,
갱신을 받아 갈 채널을 가진다.
@<게임 방과 구독자@>=
type sub struct {
	id     int
	player int
	ch     chan []byte
}

type Game struct {
	mu      sync.Mutex
	code    string
	state   *bz.State
	subs    map[int]*sub
	nextID  int
	claimed []bool       // claimed[p]가 참이면 p번 자리에 이미 임자가 있다
	bots    []bot.Policy // bots[p]가 nil이 아니면 p번 자리는 봇이다
	names   []string     // 자리마다의 표시 이름(사람은 참가 때, 봇은 만들 때 정함)
	rng     *mrand.Rand  // 봇 정책에 넘길 난수원
	chatLog []ChatMsg    // 늦게 붙는 사람에게 되보낼 최근 채팅
	chatSeq int          // 채팅 순번(재접속 시 중복 걸러내기용, 절대 되감지 않음)
	turnActive int       // 채팅이 매인 턴(활성 플레이어). 바뀌면 채팅을 비운다
	lastSeen time.Time   // 마지막 활동 시각. 오래 놀고 아무도 안 보면 청소부가 치운다
}

@ 한 플레이어에게 보내는 갱신 한 통은 그의 뷰, 직전 이벤트, 그리고 어느 자리가
봇인지 알리는 표식으로 이뤄진다. 뷰는 화면을 다시 그리는 데, 이벤트는 방금 무슨
일이 있었는지 알리는 데, 봇 표식은 클라이언트가 봇 자리를 사람과 달리 보여 주는
데 쓴다. 봇 여부는 엔진의 |View|가 모르는 서버만의 사정이라 여기에 따로 싣는다.
@<게임 방과 구독자@>=
type Message struct {
	Board  bz.View  `json:"view"`
	Events []string `json:"events"`
	Bots   []bool   `json:"bots"`  // bots[p]가 참이면 p번은 봇
	Names  []string `json:"names"` // 자리마다의 표시 이름
}

@ 구독자가 붙고 떨어지는 일을 다룬다. |register|는 새 구독자를 목록에 넣고,
접속하자마자 현재 판을 한 번 보낸 뒤 그동안 오간 채팅을 되보내 준다(새로고침
뒤에도 대화가 이어지도록). 채널은 이제 완성된 SSE 프레임을 나른다. |unregister|는
목록에서 빼고 채널을 닫는다. 둘 다 뮤텍스 아래에서 도므로 서로 엉키지 않는다.
@<게임 방과 구독자@>=
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

@ 자리 배정과 뷰 뜨기다. |claim|은 아직 비어 있는 가장 낮은 번호의 자리를 잡아
그 번호를 돌려준다(빈자리가 없으면 실패). |view|는 한 플레이어의 뷰 한 장을
안전하게 찍어 온다. 둘 다 뮤텍스 아래에서 돈다.
@<게임 방과 구독자@>=
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

@ 자리에 이름을 붙인다. 빈 이름이면 기본 자리 이름(``0번'' 따위)을 그대로 두고,
너무 길면 스무 글자로 자른다. 홑화살괄호는 지워, 이름이 클라이언트 화면에서
태그로 새는 것을 막는다(채팅 글과 달리 이름은 |innerHTML|에 박히기 때문이다).
새 이름을 모두에게 곧장 알려, 방에 있던 이들의 화면에도 바로 뜨게 한다.
@<게임 방과 구독자@>=
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

@* 수를 적용하고 알리기.
|apply|가 서버의 심장이다. 뮤텍스를 쥐고 엔진에 사람의 수를 넘긴 뒤, 성공하면
모든 구독자에게 새 뷰를 민다. 이어서 |runBots|가 봇 차례를 처리한다---다음 둘
사람이 봇이면 사람을 기다리지 않고 서버가 곧장 두어 판을 앞으로 굴린다. 불법이면
상태를 그대로 두고 오류만 돌려준다.
@<수를 적용하고 알리기@>=
func (g *Game) apply(a bz.Action) ([]string, error) {
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

@ 봇 차례를 잇는다. 지금 둘 사람이 봇인 동안, 그 봇의 정책으로 수를 골라 두고
매번 새 뷰를 민다. 사람 차례가 되거나 게임이 끝나면 멈춘다. |apply|가 이미 방
뮤텍스를 쥐고 있으므로 여기서는 다시 잠그지 않는다---봇의 수 하나하나가 구독자
화면에 차례로 나타난다.
@<수를 적용하고 알리기@>=
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

@ 방의 모든 구독자에게 각자 새 뷰를 민다. 뷰는 사람마다 다르므로(각자 자기
손패만 본다) 한 사람씩 따로 만든다. 채널은 버퍼가 있고, 느린 구독자 탓에 서버가
멈추면 안 되므로 꽉 찼으면 건너뛴다(그 구독자는 다음 갱신 때 따라잡는다).
호출자가 방 뮤텍스를 쥔 채 부른다.
@<수를 적용하고 알리기@>=
func (g *Game) broadcast(events []string) {
	for _, s := range g.subs {
		f := sseFrame("", g.encode(s.player, events))
		select {
		case s.ch <- f:
		default:
		}
	}
}

@ SSE 한 프레임을 짓는다. 상태 갱신은 이벤트 이름 없는 기본 메시지로, 채팅은
|event: chat| 줄을 앞세워 서로 다른 이벤트로 보낸다---클라이언트가 둘을 갈라
받는다. 이름이 비면 |data:| 줄만 낸다.
@<수를 적용하고 알리기@>=
func sseFrame(event string, data []byte) []byte {
	if event == "" {
		return []byte("data: " + string(data) + "\n\n")
	}
	return []byte("event: " + event + "\ndata: " + string(data) + "\n\n")
}

@ 한 통을 JSON으로 부호화한다. 뷰를 뜨는 일은 엔진의 |View|에 맡기므로 가림이
저절로 지켜지고, 봇 표식은 방이 안다. |botFlags|는 그 표식을 만든다---봇 자리는
정책이 심겨 있어 |nil|이 아니다.
@<수를 적용하고 알리기@>=
func (g *Game) encode(player int, events []string) []byte {
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

@* 게임 관리소.
|Hub|는 여러 게임 방을 {\it 방 코드\/}로 관리하고, 발급한 토큰을 세션으로
간직한다. 방 코드는 사람이 부르기 쉬운 짧은 코드고, 토큰은 한 자리의 열쇠다.
자기 뮤텍스로 방 목록과 세션을 지키되, 방 {\it 안\/}의 상태는 각 방의 뮤텍스가
지키므로 서로 간섭하지 않는다.
@s session int
@<게임 관리소@>=
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

@ 새 방을 연다. 엔진으로 게임을 차리고, 겹치지 않는 방 코드를 붙여 목록에 넣는다.
자리는 인원수만큼 마련하되, 봇 |bots|명은 {\it 높은\/} 자리에 미리 앉힌다---그래야
낮은 번호(특히 첫 수를 두는 0번)는 사람 몫으로 남는다. 사람이 적어도 하나는
있어야 판이 굴러가므로, 봇은 인원보다 적어야 한다.
@<게임 관리소@>=
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
		names:    make([]string, players), lastSeen: time.Now(),
		rng: mrand.New(mrand.NewPCG(seed, seed^0x9e3779b97f4a7c15))}
	for p := range g.names {
		g.names[p] = fmt.Sprintf("%d번", p) // 사람은 참가 때 이름으로 바뀐다
	}
	@<봇을 높은 자리에 앉힌다@>@;
	h.games[code] = g
	return code, nil
}

@ 봇 자리는 |claimed|를 미리 참으로 두어 사람이 잡지 못하게 막고, 그리디
정책을 심고, 봇마다 이름을 붙인다. 그러면 |claim|은 낮은 번호의 사람 자리부터
배정한다.
@<봇을 높은 자리에 앉힌다@>=
for p := players - bots; p < players; p++ {
	g.bots[p] = bot.NewGreedy()
	g.claimed[p] = true
	g.names[p] = fmt.Sprintf("봇 %d", p-(players-bots)+1)
}

@ 방에 참가한다. 빈자리를 하나 잡고, 그 자리의 토큰을 새로 발급해 세션에
적어 둔다. 앞으로 이 토큰이 곧 그 플레이어다---스트림도 액션도 토큰으로
신원을 확인한다. 빈자리가 없으면 실패한다.
@<게임 관리소@>=
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

@ 방은 메모리에만 있으므로, 그냥 두면 끝난 판과 버려진 방이 끝없이 쌓인다.
|reap|은 관리소를 훑어 {\it 버려진\/} 방을 방과 그 세션까지 지운다. 버려졌다고
보는 기준은 두 가지가 함께 참일 때다: 지금 보고 있는 구독자가 하나도 없고,
마지막 활동에서 |roomTTL|보다 오래 지났을 것. 활동 중인 판(봇끼리라도 수가
오가면 |lastSeen|이 갱신된다)이나 누군가 화면을 열어 둔 방은 건드리지 않는다.
@^메모리 누수@>
@<게임 관리소@>=
const (
	roomTTL    = time.Hour       // 이만큼 놀고 아무도 안 보면 버려진 방
	sweepEvery = 10 * time.Minute // 이 간격으로 방을 훑는다
)

func (h *Hub) reap(now time.Time) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for code, g := range h.games {
		g.mu.Lock()
		if len(g.subs) == 0 && now.Sub(g.lastSeen) > roomTTL {
			delete(h.games, code)
			@<이 방을 가리키는 세션을 지운다@>@;
		}
		g.mu.Unlock()
	}
}

@ 방 뮤텍스를 쥔 채로 지우므로, 지우는 사이에 새 구독자가 끼어들 틈이 없다
(구독자 등록도 같은 뮤텍스를 거친다). 관리소 뮤텍스를 먼저, 방 뮤텍스를 나중에
잡는 순서는 서버 어디서나 지켜지니, 이렇게 겹쳐 잡아도 엉키지 않는다.
@<이 방을 가리키는 세션을 지운다@>=
for tok, s := range h.sessions {
	if s.game == g {
		delete(h.sessions, tok)
	}
}

@ 청소부는 |sweepEvery|마다 깨어나 한 번씩 훑는 고루틴이다. |main|이 서버를
열기 전에 하나 띄운다.
@<게임 관리소@>=
func (h *Hub) janitor() {
	for range time.Tick(sweepEvery) {
		h.reap(time.Now())
	}
}

@ 코드와 토큰을 짓는 잔손질이다. 방 코드는 헷갈리는 글자($0$\slash O,
$1$\slash I 따위)를 뺀 네 글자라 입으로 부르기 좋고, |freshCode|는 이미 쓰는
코드를 피한다(호출자가 |Hub| 뮤텍스를 쥔 채 부른다). 토큰은 아무나 못 맞히게
암호학적 난수 열여섯 바이트를 16진수로 적는다.
@<게임 관리소@>=
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

@* HTTP 손잡이.
손잡이들은 얇다. 방을 만들거나 참가시키고, 토큰으로 신원을 확인한 뒤 엔진
계층(|apply|\slash |view|)을 불러 결과를 JSON으로 돌려줄 뿐이다. 먼저 JSON
응답 잔손질과, 토큰으로 세션을 찾는 |auth|를 묶어 둔다---신원이 확인되지 않으면
401을 돌려주고 거짓을 낸다.
@<HTTP 손잡이@>=
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

@ 토큰은 URL이 아니라 |Authorization: Bearer| 머리글에서 읽는다. SSE의
|EventSource|는 머리글을 못 실으므로, 스트림만은 쿠키 |bz_token|을 대신 받는다.
어느 쪽이든 토큰이 URL에 남지 않아 서버 로그에 새지 않는다.
@<HTTP 손잡이@>=
func requestToken(r *http.Request) string {
	if h := r.Header.Get("Authorization"); strings.HasPrefix(h, "Bearer ") {
		return strings.TrimPrefix(h, "Bearer ")
	}
	if c, err := r.Cookie("bz_token"); err == nil {
		return c.Value
	}
	return ""
}

@ 새 게임. 인원\slash 봇수\slash 씨앗을 질의에서 읽어 방을 열고 방 코드를
돌려준다. 봇수를 안 주면 0(사람만)이다. 방을 만든 사람도 따로 참가해 자리를
잡아야 한다(클라이언트가 곧바로 참가를 부른다).
@<HTTP 손잡이@>=
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

@ 참가. 방 코드로 빈자리를 하나 잡아, 배정된 자리 번호와 토큰을 돌려준다.
클라이언트는 이 토큰을 간직했다가 이후 모든 요청에 실어 보낸다(새로고침 뒤
다시 붙을 때도 같은 토큰을 그대로 쓰면 된다).
@<HTTP 손잡이@>=
func (h *Hub) handleJoin(w http.ResponseWriter, r *http.Request) {
	player, tok, err := h.join(r.PathValue("code"), r.URL.Query().Get("name"))
	if err != nil {
		http.Error(w, err.Error(), http.StatusConflict)
		return
	}
	writeJSON(w, map[string]any{"player": player, "token": tok})
}

@ 뷰 한 장을 찍어 준다. 토큰으로 신원을 확인하고 그 플레이어의 뷰를 준다.
@<HTTP 손잡이@>=
func (h *Hub) handleView(w http.ResponseWriter, r *http.Request) {
	g, player, ok := h.auth(w, r)
	if !ok {
		return
	}
	writeJSON(w, g.view(player))
}

@ 액션을 받는다. 토큰이 임자를 정하므로, 본문에 어떤 |player|가 적혀 있든 서버가
토큰의 자리로 {\it 덮어쓴다\/}---남의 자리로 두는 것을 원천 봉쇄한다. 불법이면
409로 되돌린다. 성공하면 그 플레이어의 새 뷰와 이벤트를 즉답으로 주고, 나머지
구독자들은 스트림으로 갱신을 받는다.
@<HTTP 손잡이@>=
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
	writeJSON(w, Message{Board: g.view(player), Events: events, Bots: g.botFlags()})
}

@ 뷰 스트림. 토큰으로 신원을 확인한 뒤 SSE 머리글을 세우고 구독자로 등록한다.
채널로 오는 갱신을 그대로 |data:| 줄에 실어 흘려보내고, 접속이 끊기면(요청
맥락이 닫히면) 구독을 푼다.
@<HTTP 손잡이@>=
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
	@<SSE 머리글을 세우고 갱신을 흘려보낸다@>@;
}

@ SSE 규약대로 |text/event-stream| 머리글을 세우고, 구독자로 등록한다. 그다음
채널이 닫힐 때(구독 해제)나 접속이 끊길 때까지 프레임을 그대로 내보내며 그때마다
버퍼를 비운다(flush). 프레임은 이미 |sseFrame|이 규약에 맞게 지어 두었다.
@<SSE 머리글을 세우고 갱신을 흘려보낸다@>=
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

@ 콩 도감. 이름\slash 장수\slash 콩미터 같은 고정 정보라, 클라이언트가 처음에
한 번만 받아 두면 된다.
@<HTTP 손잡이@>=
func handleCatalog(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, bz.Catalog())
}

@* 채팅.
거래는 흥정이라 말이 오간다. 참가자들이 서로 대화하도록 방마다 채팅을 얹는다.
상태 갱신과 같은 SSE 관을 쓰되 |event: chat|으로 갈라 보내고, 늦게 붙는 사람을
위해 최근 몇 줄을 방에 간직해 접속할 때 되보낸다. 봇은 말하지 않는다.
@<채팅@>=
type ChatMsg struct {
	Seq  int    `json:"seq"` // 방 안에서 늘 커지는 순번
	From int    `json:"from"`
	Text string `json:"text"`
}

@ 채팅 한 줄을 방에 적고 모두에게 민다. 순번을 하나 올려 붙이므로, 재접속으로
이력을 다시 받아도 클라이언트가 이미 본 줄을 순번으로 걸러낼 수 있다. 이력은
최근 서른 줄만 남긴다. 채팅 프레임은 사람마다 다르지 않으므로 한 번 지어 모두에게
같은 것을 보낸다.
@<채팅@>=
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

@ 턴이 바뀌면 채팅을 새로 시작한다. 활성 플레이어가 달라졌으면(곧 새 턴이면)
지난 턴의 흥정 기록을 비운다---거래 협상은 그 턴에 매인 것이라, 턴이 넘어가면
깨끗한 판에서 다시 시작하는 편이 보기에 낫다. 순번은 되감지 않으므로 클라이언트의
중복 거르기는 그대로다. 호출자가 방 뮤텍스를 쥔 채, 수를 둔 직후에 부른다.
@<채팅@>=
func (g *Game) rolloverChat() {
	if g.state.Active != g.turnActive {
		g.turnActive = g.state.Active
		g.chatLog = nil
	}
}

@ 채팅 손잡이. 토큰으로 신원을 확인하고, 본문에서 글을 읽어 다듬은 뒤 방에
알린다. 빈 글은 무시하고, 너무 길면 잘라 악용을 막는다---글자(룬) 단위로 잘라
한글도 깨지지 않는다.
@<채팅@>=
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
	@<채팅 글을 다듬어 방에 알린다@>@;
}

@ 앞뒤 공백을 떼고, 빈 글은 조용히 흘린다. 너무 길면 300글자로 자른다.
@<채팅 글을 다듬어 방에 알린다@>=
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

@* 문 열기.
|main|은 길을 잇고 문을 연다. 주소는 인수로 받되 없으면 |:8080|이다. \GO/
1.22부터 |ServeMux|가 메서드와 경로 변수를 함께 받으므로, 라우팅도 표준
라이브러리만으로 깔끔하다. 정적 파일은 앞단 nginx가 맡으므로, 여기에는 게임
API 길만 잇는다.
@<문 열기@>=
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

@* 색인.
