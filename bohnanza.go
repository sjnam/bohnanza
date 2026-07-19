//line bohnanza.w:39
package bohnanza

import (
	"encoding/json"
	"fmt"
	"math/rand/v2"
	"strings"
)

//line bohnanza.w:74
type Bean int

const (
	Coffee Bean = iota
	Wax
	Blue
	Chili
	Stink
	Green
	Soy
	BlackEyed
	Red
	Garden
	Cocoa
	NumBeans

//line bohnanza.w:89
)

type Card = Bean // |Card|는 콩 한 알과 같다.

//line bohnanza.w:96
type BeanInfo struct {
	Name  string
	Count int    // 덱에 들어가는 장수
	Meter [4]int // 1,2,3,4 코인에 필요한 장수 (0은 도달 불가)
}

var beanTable = [NumBeans]BeanInfo{
	Coffee:    {"커피콩", 24, [4]int{4, 7, 10, 12}},
	Wax:       {"왁스콩", 22, [4]int{4, 7, 9, 11}},
	Blue:      {"파랑콩", 20, [4]int{4, 6, 8, 10}},
	Chili:     {"고추콩", 18, [4]int{3, 6, 8, 9}},
	Stink:     {"악취콩", 16, [4]int{3, 5, 7, 8}},
	Green:     {"완두콩", 14, [4]int{3, 5, 6, 7}},
	Soy:       {"메주콩", 12, [4]int{2, 4, 6, 7}},
	BlackEyed: {"동부콩", 10, [4]int{2, 4, 5, 6}},
	Red:       {"강낭콩", 8, [4]int{2, 3, 4, 5}},
	Garden:    {"정원콩", 6, [4]int{0, 2, 3, 0}},
	Cocoa:     {"카카오콩", 4, [4]int{0, 2, 3, 4}},
}

const TotalCards = 154 // 덱 전체 장수(154)다.

//line bohnanza.w:122
func (b Bean) Name() string { return beanTable[b].Name }

func (b Bean) Coins(n int) int {
	c := 0
	for i, need := range beanTable[b].Meter {
		if need != 0 && n >= need {
			c = i + 1
		}
	}
	return c
}

//line bohnanza.w:147
type Field struct {
	Crop  Bean // 이 밭에서 자라는 콩(작물)
	Count int
}

func (f Field) Empty() bool { return f.Count == 0 }

type Player struct {
	Hand     []Card  // 순서 고정: 맨 앞에서만 꺼낸다
	Fields   []Field // 처음 2칸, 3번째 밭을 사면 3칸
	Acquired []Card  // 거래로 받아 아직 못 심은 콩
	Treasury []Card  // 거두어 모은 코인
}

func (p *Player) Coins() int { return len(p.Treasury) }

//line bohnanza.w:168
type Phase int

const (
	PhasePlant        Phase = iota // 손패에서 심기
	PhaseTrade                     // 공개 카드 나누기
	PhaseHarvestGifts              // 받은 콩 심기
	GameOver

//line bohnanza.w:175
)

//line bohnanza.w:179
func (p Phase) String() string {
	switch p {
	case PhasePlant:
		return "심기"
	case PhaseTrade:
		return "거래"
	case PhaseHarvestGifts:
		return "받은 콩 심기"
	}
	return "종료"
}

//line bohnanza.w:196
type State struct {
	Players    []*Player
	Deck       []Card
	Discard    []Card
	FaceUp     []Card // 거래에서 뒤집은 공개 카드
	Removed    []Card // 게임에서 빠진 카드(밭 값)
	Active     int
	Stage      Phase // 지금 이 턴이 어느 단계인지
	PlantCount int
	Exhaust    int
	Pending    *Proposal // 응답을 기다리는 거래 제안(없으면 |nil|)

	rng *rand.Rand
}

//line bohnanza.w:216
type Proposal struct {
	From       int
	To         int
	GiveHand   []Card // From이 손패에서 내주는 콩
	GiveFaceUp []Card // From이 공개 카드에서 내주는 콩
	GetHand    []Card // To가 손패에서 내주는 콩
}

//line bohnanza.w:228
const StartingHand = 5

func New(numPlayers int, seed uint64) (*State, error) {
	if numPlayers < 2 || numPlayers > 4 {
		return nil, fmt.Errorf("보난자: 인원은 2~4명이어야 한다 (%d명 요청)", numPlayers)
	}
	s := &State{rng: rand.New(rand.NewPCG(seed, seed^0x9e3779b97f4a7c15))}

//line bohnanza.w:242
	for b := Bean(0); b < NumBeans; b++ {
		for i := 0; i < beanTable[b].Count; i++ {
			s.Deck = append(s.Deck, b)
		}
	}
	s.rng.Shuffle(len(s.Deck), func(i, j int) {
		s.Deck[i], s.Deck[j] = s.Deck[j], s.Deck[i]
	})

//line bohnanza.w:236

//line bohnanza.w:253
	for i := 0; i < numPlayers; i++ {
		s.Players = append(s.Players, &Player{Fields: make([]Field, 2)})
	}
	for k := 0; k < StartingHand; k++ {
		for i := 0; i < numPlayers; i++ {
			c, _ := s.draw()
			s.Players[i].Hand = append(s.Players[i].Hand, c)
		}
	}

//line bohnanza.w:237
	return s, nil
}

//line bohnanza.w:268
func (s *State) draw() (Card, bool) {
	if len(s.Deck) == 0 {
		s.Exhaust++
		if s.Exhaust >= 3 || len(s.Discard) == 0 {
			return 0, false
		}
		s.Deck, s.Discard = s.Discard, nil
		s.rng.Shuffle(len(s.Deck), func(i, j int) {
			s.Deck[i], s.Deck[j] = s.Deck[j], s.Deck[i]
		})
	}
	c := s.Deck[len(s.Deck)-1]
	s.Deck = s.Deck[:len(s.Deck)-1]
	return c, true
}

//line bohnanza.w:287
func (s *State) endIfEmpty(ok bool) bool {
	if !ok {
		s.Stage = GameOver
	}
	return ok
}

//line bohnanza.w:299
func (s *State) plant(p *Player, field int, b Bean) error {
	if field < 0 || field >= len(p.Fields) {
		return fmt.Errorf("보난자: 밭 번호 %d가 범위를 벗어남", field)
	}
	f := &p.Fields[field]
	switch {
	case f.Empty():
		f.Crop, f.Count = b, 1
	case f.Crop == b:
		f.Count++
	default:
		return fmt.Errorf("보난자: %s 밭에 %s를 심을 수 없음", f.Crop.Name(), b.Name())
	}
	return nil
}

//line bohnanza.w:320
func (p *Player) canHarvest(field int) bool {
	f := p.Fields[field]
	if f.Count == 0 {
		return false
	}
	if f.Count == 1 {
		for j := range p.Fields {
			if j != field && p.Fields[j].Count > 1 {
				return false
			}
		}
	}
	return true
}

//line bohnanza.w:344
func (s *State) harvest(p *Player, field int) (int, error) {
	if field < 0 || field >= len(p.Fields) {
		return 0, fmt.Errorf("보난자: 밭 번호 %d가 범위를 벗어남", field)
	}
	if !p.canHarvest(field) {
		return 0, fmt.Errorf("보난자: 다른 밭에 두 장 이상 있으면 한 장짜리 밭은 못 거둠")
	}
	f := &p.Fields[field]
	coins := f.Crop.Coins(f.Count)
	for i := 0; i < coins; i++ {
		p.Treasury = append(p.Treasury, f.Crop)
	}
	for i := 0; i < f.Count-coins; i++ {
		s.Discard = append(s.Discard, f.Crop)
	}
	*f = Field{}
	return coins, nil
}

//line bohnanza.w:368
func (s *State) endTurn() {
	p := s.Players[s.Active]
	for i := 0; i < 3; i++ {
		c, ok := s.draw()
		if !s.endIfEmpty(ok) {
			return
		}
		p.Hand = append(p.Hand, c)
	}
	s.Active = (s.Active + 1) % len(s.Players)
	s.Stage = PhasePlant
	s.PlantCount = 0
}

//line bohnanza.w:387
func (s *State) ToAct() int {
	switch s.Stage {
	case PhasePlant:
		return s.Active
	case PhaseTrade:
		if s.Pending != nil {
			return s.Pending.To // 제안을 기다리는 동안은 상대 차례
		}
		return s.Active
	case PhaseHarvestGifts:
		for i := range s.Players {
			if len(s.Players[i].Acquired) > 0 {
				return i
			}
		}
	}
	return -1
}

//line bohnanza.w:408
func (s *State) giftsPending() bool {
	for i := range s.Players {
		if len(s.Players[i].Acquired) > 0 {
			return true
		}
	}
	return false
}

//line bohnanza.w:425
type ActionKind int

const (
	PlantFront   ActionKind = iota // 손패 맨 앞을 밭에 심기
	Harvest                        // 밭 거두기
	BuyField                       // 코인 3으로 세 번째 밭 사기
	EndPhase                       // 현재 단계 끝내기
	TakeRevealed                   // 공개 카드를 내 밭에 심기
	ProposeTrade                   // 거래(교환 또는 기부)를 제안
	RespondTrade                   // 제안을 수락 또는 거절
	PlantGift                      // 받은 콩을 밭에 심기
)

type Action struct {
	Kind     ActionKind `json:"kind"`
	Actor    int        `json:"player"` // 이 수를 두는 사람
	FieldNo  int        `json:"field"`  // 심거나 거둘 밭 번호
	FaceUpNo int        `json:"card"`   // |TakeRevealed|에서 공개 카드 번호
	To       int        `json:"to"`     // 거래 상대

	// |ProposeTrade|용: 주고받을 콩을 값으로 적는다.
	GiveHand   []Card `json:"giveHand,omitempty"`
	GiveFaceUp []Card `json:"giveFaceUp,omitempty"`
	GetHand    []Card `json:"getHand,omitempty"`

	Accept bool `json:"accept,omitempty"` // |RespondTrade|용: 수락 여부
}

//line bohnanza.w:455
func (a Action) String() string {
	switch a.Kind {
	case PlantFront:
		return fmt.Sprintf("맨 앞 카드를 %d번 밭에 심기", a.FieldNo)
	case Harvest:
		return fmt.Sprintf("%d번 밭 거두기", a.FieldNo)
	case BuyField:
		return "세 번째 밭 사기(코인 3)"
	case EndPhase:
		return "이 단계 끝내기"
	case TakeRevealed:
		return fmt.Sprintf("공개 카드 %d번을 %d번 밭에 심기", a.FaceUpNo, a.FieldNo)
	case ProposeTrade:
		return a.tradeString()
	case RespondTrade:
		if a.Accept {
			return "제안 수락"
		}
		return "제안 거절"
	case PlantGift:
		return fmt.Sprintf("받은 콩을 %d번 밭에 심기", a.FieldNo)
	}
	return "알 수 없는 수"
}

//line bohnanza.w:483
func beanNames(cs []Card) string {
	if len(cs) == 0 {
		return "없음"
	}
	names := make([]string, len(cs))
	for i, c := range cs {
		names[i] = c.Name()
	}
	return strings.Join(names, ",")
}

func (a Action) tradeString() string {
	give := append(append([]Card{}, a.GiveHand...), a.GiveFaceUp...)
	return fmt.Sprintf("%d번에게 [%s] 주고 [%s] 받기 제안",
		a.To, beanNames(give), beanNames(a.GetHand))
}

//line bohnanza.w:505
func (s *State) Legal(player int) []Action {
	if s.Stage == GameOver || player != s.ToAct() {
		return nil
	}
	switch s.Stage {
	case PhasePlant:
		return s.legalPlant(player)
	case PhaseTrade:
		if s.Pending != nil {
			return s.legalRespond(player)
		}
		return s.legalTrade(player)
	case PhaseHarvestGifts:
		return s.legalGifts(player)
	}
	return nil
}

//line bohnanza.w:528
func (s *State) legalPlant(player int) []Action {
	p := s.Players[player]
	var acts []Action
	if s.PlantCount < 2 && len(p.Hand) > 0 {
		front := p.Hand[0]
		for f := range p.Fields {
			if p.Fields[f].Empty() || p.Fields[f].Crop == front {
				acts = append(acts, Action{Kind: PlantFront, Actor: player, FieldNo: f})
			}
		}
	}
	acts = append(acts, s.harvestActions(player)...)
	if len(p.Fields) == 2 && p.Coins() >= 3 {
		acts = append(acts, Action{Kind: BuyField, Actor: player})
	}
	if s.PlantCount >= 1 || len(p.Hand) == 0 {
		acts = append(acts, Action{Kind: EndPhase, Actor: player})
	}
	return acts
}

//line bohnanza.w:552
func (s *State) harvestActions(player int) []Action {
	p := s.Players[player]
	var acts []Action
	for f := range p.Fields {
		if p.canHarvest(f) {
			acts = append(acts, Action{Kind: Harvest, Actor: player, FieldNo: f})
		}
	}
	return acts
}

//line bohnanza.w:567
func (s *State) legalTrade(player int) []Action {
	var acts []Action
	for c := range s.FaceUp {
		acts = append(acts, s.takeActions(player, c)...)
	}
	acts = append(acts, s.harvestActions(player)...)
	acts = append(acts, s.proposeActions(player)...)
	if len(s.FaceUp) == 0 {
		acts = append(acts, Action{Kind: EndPhase, Actor: player})
	}
	return acts
}

//line bohnanza.w:586
func (s *State) legalRespond(player int) []Action {
	var acts []Action
	if s.Pending != nil && containsAll(s.Players[player].Hand, s.Pending.GetHand) {
		acts = append(acts, Action{Kind: RespondTrade, Actor: player, Accept: true})
	}
	return append(acts, Action{Kind: RespondTrade, Actor: player, Accept: false})
}

//line bohnanza.w:596
func (s *State) takeActions(player, card int) []Action {
	p := s.Players[player]
	b := s.FaceUp[card]
	var acts []Action
	for f := range p.Fields {
		if p.Fields[f].Empty() || p.Fields[f].Crop == b {
			acts = append(acts, Action{Kind: TakeRevealed, Actor: player, FaceUpNo: card, FieldNo: f})
		}
	}
	return acts
}

//line bohnanza.w:613
func (s *State) proposeActions(player int) []Action {
	var acts []Action
	mine := distinct(s.Players[player].Hand)
	faceup := distinct(s.FaceUp)
	for to := range s.Players {
		if to == player {
			continue
		}
		theirs := distinct(s.Players[to].Hand)

//line bohnanza.w:630
		for _, gb := range mine {
			for _, tb := range theirs {
				acts = append(acts, Action{Kind: ProposeTrade, Actor: player, To: to,
					GiveHand: []Card{gb}, GetHand: []Card{tb}})
			}
			acts = append(acts, Action{Kind: ProposeTrade, Actor: player, To: to,
				GiveHand: []Card{gb}})
		}
		for _, gb := range faceup {
			for _, tb := range theirs {
				acts = append(acts, Action{Kind: ProposeTrade, Actor: player, To: to,
					GiveFaceUp: []Card{gb}, GetHand: []Card{tb}})
			}
			acts = append(acts, Action{Kind: ProposeTrade, Actor: player, To: to,
				GiveFaceUp: []Card{gb}})
		}

//line bohnanza.w:623
	}
	return acts
}

//line bohnanza.w:650
func distinct(cs []Card) []Card {
	seen := make(map[Card]bool)
	var out []Card
	for _, c := range cs {
		if !seen[c] {
			seen[c] = true
			out = append(out, c)
		}
	}
	return out
}

//line bohnanza.w:665
func (s *State) legalGifts(player int) []Action {
	p := s.Players[player]
	var acts []Action
	b := p.Acquired[0]
	for f := range p.Fields {
		if p.Fields[f].Empty() || p.Fields[f].Crop == b {
			acts = append(acts, Action{Kind: PlantGift, Actor: player, FieldNo: f})
		}
	}
	acts = append(acts, s.harvestActions(player)...)
	return acts
}

//line bohnanza.w:690
type EventKind string

//line bohnanza.w:696
const (
	Planted       EventKind = "planted"       // 손패 맨 앞 카드를 밭에 심음
	PlantedFaceUp EventKind = "plantedFaceUp" // 공개 카드를 밭에 심음
	PlantedGift   EventKind = "plantedGift"   // 거래로 받은 콩을 밭에 심음
	Harvested     EventKind = "harvested"     // 밭을 거두어 코인을 얻음
	BoughtField   EventKind = "boughtField"   // 세 번째 밭을 삼
	Revealed      EventKind = "revealed"      // 덱에서 공개 카드가 뒤집힘
	DeckEmptied   EventKind = "deckEmptied"   // 덱이 바닥나 게임이 끝남
	GiftStage     EventKind = "giftStage"     // 받은 콩을 심는 단계로 넘어감
	TurnPassed    EventKind = "turnPassed"    // 턴을 넘김
	TradeProposed EventKind = "tradeProposed" // 거래를 제안
	TradeRejected EventKind = "tradeRejected" // 제안을 거절
	TradeAccepted EventKind = "tradeAccepted" // 교환 성사
)

//line bohnanza.w:716
const NoActor = -1

type Event struct {
	Kind    EventKind `json:"kind"`
	Actor   int       `json:"actor"`          // 이 일을 한 사람
	To      int       `json:"to"`             // 거래 상대
	Crop    Bean      `json:"bean"`           // 이 일에 걸린 콩
	FieldNo int       `json:"field"`          // 심거나 거둔 밭 번호
	Coins   int       `json:"coins"`          // 거두어 얻은 코인
	Give    []Card    `json:"give,omitempty"` // 제안자가 내주는 콩
	Get     []Card    `json:"get,omitempty"`  // 제안자가 받는 콩
}

//line bohnanza.w:734
func (e Event) String() string {
	switch e.Kind {

//line bohnanza.w:742
	case Planted, PlantedFaceUp, PlantedGift:
		return fmt.Sprintf("%d번이 %s%s %d번 밭에 심음", e.Actor,
			e.Crop.Name(), objectParticle(e.Crop.Name()), e.FieldNo)
	case Harvested:
		return fmt.Sprintf("%d번이 %s 밭을 거둬 코인 %d개 얻음",
			e.Actor, e.Crop.Name(), e.Coins)
	case BoughtField:
		return fmt.Sprintf("%d번이 세 번째 밭을 삼", e.Actor)
	case Revealed:
		return fmt.Sprintf("공개 카드로 %s%s 뒤집힘",
			e.Crop.Name(), subjectParticle(e.Crop.Name()))

//line bohnanza.w:756
	case TradeProposed:
		return fmt.Sprintf("%d번이 %d번에게 [%s] 주고 [%s] 받기를 제안",
			e.Actor, e.To, beanNames(e.Give), beanNames(e.Get))
	case TradeRejected:
		return fmt.Sprintf("%d번이 제안을 거절", e.Actor)
	case TradeAccepted:
		return fmt.Sprintf("%d번과 %d번이 [%s] 주고 [%s] 받아 교환 성사",
			e.Actor, e.To, beanNames(e.Give), beanNames(e.Get))
	case DeckEmptied:
		return "덱이 바닥나 게임이 끝남"
	case GiftStage:
		return "받은 콩을 심는 단계로"
	case TurnPassed:
		return "턴을 넘김"

//line bohnanza.w:737
	}
	return string(e.Kind)
}

//line bohnanza.w:777
func hasFinal(name string) bool {
	r := []rune(name)
	if len(r) == 0 {
		return false
	}
	last := r[len(r)-1]
	if last < 0xAC00 || last > 0xD7A3 {
		return false // 한글 음절이 아니다
	}
	return (last-0xAC00)%28 != 0
}

func objectParticle(name string) string {
	if hasFinal(name) {
		return "을"
	}
	return "를"
}

func subjectParticle(name string) string {
	if hasFinal(name) {
		return "이"
	}
	return "가"
}

//line bohnanza.w:808
func (s *State) Apply(a Action) ([]Event, error) {
	if s.Stage == GameOver {
		return nil, fmt.Errorf("보난자: 게임이 이미 끝남")
	}
	if a.Actor != s.ToAct() {
		return nil, fmt.Errorf("보난자: 지금은 %d번 플레이어 차례가 아님", a.Actor)
	}
	if s.Pending != nil && a.Kind != RespondTrade {
		return nil, fmt.Errorf("보난자: 먼저 거래 제안에 응답해야 함")
	}
	switch a.Kind {
	case PlantFront:
		return s.applyPlantFront(a)
	case Harvest:
		return s.applyHarvest(a)
	case BuyField:
		return s.applyBuyField(a)
	case EndPhase:
		return s.applyEndPhase(a)
	case TakeRevealed:
		return s.applyTake(a)
	case ProposeTrade:
		return s.applyPropose(a)
	case RespondTrade:
		return s.applyRespond(a)
	case PlantGift:
		return s.applyPlantGift(a)
	}
	return nil, fmt.Errorf("보난자: 알 수 없는 액션")
}

//line bohnanza.w:842
func (s *State) applyPlantFront(a Action) ([]Event, error) {
	p := s.Players[s.Active]
	if s.PlantCount >= 2 {
		return nil, fmt.Errorf("보난자: 한 턴에 두 장까지만 심을 수 있음")
	}
	if len(p.Hand) == 0 {
		return nil, fmt.Errorf("보난자: 손패가 비어 심을 수 없음")
	}
	b := p.Hand[0]
	if err := s.plant(p, a.FieldNo, b); err != nil {
		return nil, err
	}
	p.Hand = p.Hand[1:]
	s.PlantCount++
	return []Event{{Kind: Planted, Actor: a.Actor, To: NoActor,
		Crop: b, FieldNo: a.FieldNo}}, nil
}

//line bohnanza.w:862
func (s *State) applyHarvest(a Action) ([]Event, error) {
	p := s.Players[a.Actor]
	b := p.Fields[a.FieldNo].Crop
	coins, err := s.harvest(p, a.FieldNo)
	if err != nil {
		return nil, err
	}
	return []Event{{Kind: Harvested, Actor: a.Actor, To: NoActor,
		Crop: b, FieldNo: a.FieldNo, Coins: coins}}, nil
}

//line bohnanza.w:875
func (s *State) applyBuyField(a Action) ([]Event, error) {
	p := s.Players[s.Active]
	if len(p.Fields) != 2 {
		return nil, fmt.Errorf("보난자: 세 번째 밭은 한 번만 살 수 있음")
	}
	if p.Coins() < 3 {
		return nil, fmt.Errorf("보난자: 코인이 부족함")
	}
	n := len(p.Treasury)
	s.Removed = append(s.Removed, p.Treasury[n-3:]...)
	p.Treasury = p.Treasury[:n-3]
	p.Fields = append(p.Fields, Field{})
	return []Event{{Kind: BoughtField, Actor: a.Actor, To: NoActor}}, nil
}

//line bohnanza.w:893
func (s *State) applyEndPhase(a Action) ([]Event, error) {
	switch s.Stage {
	case PhasePlant:
		p := s.Players[s.Active]
		if s.PlantCount < 1 && len(p.Hand) > 0 {
			return nil, fmt.Errorf("보난자: 맨 앞 카드를 먼저 심어야 함")
		}
		return s.flipAndTrade()
	case PhaseTrade:
		return s.endTradePhase()
	}
	return nil, fmt.Errorf("보난자: 이 단계는 끝낼 수 없음")
}

//line bohnanza.w:909
func (s *State) flipAndTrade() ([]Event, error) {
	var ev []Event
	for i := 0; i < 2; i++ {
		c, ok := s.draw()
		if !s.endIfEmpty(ok) {
			return append(ev, Event{Kind: DeckEmptied,
				Actor: NoActor, To: NoActor}), nil
		}
		s.FaceUp = append(s.FaceUp, c)
		ev = append(ev, Event{Kind: Revealed,
			Actor: NoActor, To: NoActor, Crop: c})
	}
	s.Stage = PhaseTrade
	return ev, nil
}

//line bohnanza.w:928
func (s *State) endTradePhase() ([]Event, error) {
	if len(s.FaceUp) > 0 {
		return nil, fmt.Errorf("보난자: 공개 카드를 모두 처리해야 함")
	}
	if s.giftsPending() {
		s.Stage = PhaseHarvestGifts
		return []Event{{Kind: GiftStage, Actor: NoActor, To: NoActor}}, nil
	}
	s.endTurn()
	return []Event{{Kind: TurnPassed, Actor: NoActor, To: NoActor}}, nil
}

//line bohnanza.w:943
func (s *State) applyTake(a Action) ([]Event, error) {
	p := s.Players[s.Active]
	if a.FaceUpNo < 0 || a.FaceUpNo >= len(s.FaceUp) {
		return nil, fmt.Errorf("보난자: 공개 카드 번호가 범위를 벗어남")
	}
	b := s.FaceUp[a.FaceUpNo]
	if err := s.plant(p, a.FieldNo, b); err != nil {
		return nil, err
	}
	s.FaceUp = removeCard(s.FaceUp, a.FaceUpNo)
	return []Event{{Kind: PlantedFaceUp, Actor: a.Actor, To: NoActor,
		Crop: b, FieldNo: a.FieldNo}}, nil
}

//line bohnanza.w:965
func (s *State) applyPropose(a Action) ([]Event, error) {
	if a.To == s.Active || a.To < 0 || a.To >= len(s.Players) {
		return nil, fmt.Errorf("보난자: 거래 상대가 잘못됨")
	}
	if len(a.GiveHand)+len(a.GiveFaceUp)+len(a.GetHand) == 0 {
		return nil, fmt.Errorf("보난자: 빈 거래는 제안할 수 없음")
	}

//line bohnanza.w:986
	if !containsAll(s.Players[s.Active].Hand, a.GiveHand) {
		return nil, fmt.Errorf("보난자: 내 손패에 없는 콩을 줄 수 없음")
	}
	if !containsAll(s.FaceUp, a.GiveFaceUp) {
		return nil, fmt.Errorf("보난자: 공개되지 않은 콩을 줄 수 없음")
	}

//line bohnanza.w:973
	s.Pending = &Proposal{From: s.Active, To: a.To,
		GiveHand:   append([]Card{}, a.GiveHand...),
		GiveFaceUp: append([]Card{}, a.GiveFaceUp...),
		GetHand:    append([]Card{}, a.GetHand...)}
	give := append(append([]Card{}, a.GiveHand...), a.GiveFaceUp...)
	return []Event{{Kind: TradeProposed, Actor: s.Active, To: a.To,
		Give: give, Get: append([]Card{}, a.GetHand...)}}, nil
}

//line bohnanza.w:996
func (s *State) applyRespond(a Action) ([]Event, error) {
	pr := s.Pending
	if pr == nil {
		return nil, fmt.Errorf("보난자: 응답할 제안이 없음")
	}
	if !a.Accept {
		s.Pending = nil
		return []Event{{Kind: TradeRejected, Actor: a.Actor, To: NoActor}}, nil
	}

//line bohnanza.w:1015
	from, to := s.Players[pr.From], s.Players[pr.To]
	if !containsAll(from.Hand, pr.GiveHand) ||
		!containsAll(s.FaceUp, pr.GiveFaceUp) ||
		!containsAll(to.Hand, pr.GetHand) {
		return nil, fmt.Errorf("보난자: 요구한 콩이 상대에게 없어 수락할 수 없음")
	}
	from.Hand = removeBeans(from.Hand, pr.GiveHand)
	s.FaceUp = removeBeans(s.FaceUp, pr.GiveFaceUp)
	to.Hand = removeBeans(to.Hand, pr.GetHand)
	to.Acquired = append(to.Acquired, pr.GiveHand...)
	to.Acquired = append(to.Acquired, pr.GiveFaceUp...)
	from.Acquired = append(from.Acquired, pr.GetHand...)
	s.Pending = nil
	give := append(append([]Card{}, pr.GiveHand...), pr.GiveFaceUp...)
	return []Event{{Kind: TradeAccepted, Actor: pr.From, To: pr.To,
		Give: give, Get: append([]Card{}, pr.GetHand...)}}, nil

//line bohnanza.w:1006
}

//line bohnanza.w:1035
func containsAll(pool, want []Card) bool {
	cnt := make(map[Card]int)
	for _, c := range pool {
		cnt[c]++
	}
	for _, c := range want {
		cnt[c]--
		if cnt[c] < 0 {
			return false
		}
	}
	return true
}

func removeBeans(pool, drop []Card) []Card {
	out := append([]Card{}, pool...)
	for _, d := range drop {
		for i, c := range out {
			if c == d {
				out = append(out[:i], out[i+1:]...)
				break
			}
		}
	}
	return out
}

//line bohnanza.w:1065
func (s *State) applyPlantGift(a Action) ([]Event, error) {
	p := s.Players[a.Actor]
	b := p.Acquired[0]
	if err := s.plant(p, a.FieldNo, b); err != nil {
		return nil, err
	}
	p.Acquired = p.Acquired[1:]
	ev := []Event{{Kind: PlantedGift, Actor: a.Actor, To: NoActor,
		Crop: b, FieldNo: a.FieldNo}}
	if !s.giftsPending() {
		s.endTurn()
		ev = append(ev, Event{Kind: TurnPassed, Actor: NoActor, To: NoActor})
	}
	return ev, nil
}

//line bohnanza.w:1083
func removeCard(cs []Card, i int) []Card {
	return append(cs[:i:i], cs[i+1:]...)
}

//line bohnanza.w:1091
func (s *State) Over() bool { return s.Stage == GameOver }

func (s *State) Scores() []int {
	sc := make([]int, len(s.Players))
	for i, p := range s.Players {
		sc[i] = p.Coins()
		for _, f := range p.Fields {
			sc[i] += f.Crop.Coins(f.Count)
		}
	}
	return sc
}

//line bohnanza.w:1107
func (s *State) countCards() int {
	n := len(s.Deck) + len(s.Discard) + len(s.FaceUp) + len(s.Removed)
	for _, p := range s.Players {
		n += len(p.Hand) + len(p.Acquired) + len(p.Treasury)
		for _, f := range p.Fields {
			n += f.Count
		}
	}
	return n
}

func (s *State) Check() error {
	if n := s.countCards(); n != TotalCards {
		return fmt.Errorf("보난자: 카드 보존 위반, %d장(154장이어야 함)", n)
	}
	return nil
}

//line bohnanza.w:1136
type FieldView struct {
	Crop  Bean `json:"bean"` // Count가 0이면 빈 밭이라 의미 없음
	Count int  `json:"count"`
}

type PlayerView struct {
	Index     int         `json:"index"`
	IsYou     bool        `json:"isYou"`
	Fields    []FieldView `json:"fields"`
	Coins     int         `json:"coins"`
	Acquired  []Bean      `json:"acquired"`
	HandCount int         `json:"handCount"`
	Hand      []Bean      `json:"hand,omitempty"` // 본인만 채워진다
}

//line bohnanza.w:1154
type ProposalView struct {
	From       int    `json:"from"`
	To         int    `json:"to"`
	GiveHand   []Bean `json:"giveHand"`
	GiveFaceUp []Bean `json:"giveFaceUp"`
	GetHand    []Bean `json:"getHand"`
}

//line bohnanza.w:1165
type View struct {
	You          int           `json:"you"`
	Active       int           `json:"active"`
	ToAct        int           `json:"toAct"`
	Stage        Phase         `json:"phase"`
	PhaseName    string        `json:"phaseName"`
	Players      []PlayerView  `json:"players"`
	FaceUp       []Bean        `json:"faceUp"`
	DeckCount    int           `json:"deckCount"`
	DiscardCount int           `json:"discardCount"`
	Pending      *ProposalView `json:"pending,omitempty"`
	Legal        []Action      `json:"legal"`
	Over         bool          `json:"over"`
	Scores       []int         `json:"scores,omitempty"`
}

//line bohnanza.w:1184
func (s *State) View(player int) View {
	v := View{
		You:          player,
		Active:       s.Active,
		ToAct:        s.ToAct(),
		Stage:        s.Stage,
		PhaseName:    s.Stage.String(),
		FaceUp:       append([]Bean{}, s.FaceUp...),
		DeckCount:    len(s.Deck),
		DiscardCount: len(s.Discard),
		Legal:        s.Legal(player),
		Over:         s.Over(),
	}
	for i, p := range s.Players {
		v.Players = append(v.Players, s.playerView(i, p, player))
	}

//line bohnanza.w:1206
	if s.Pending != nil {
		pr := s.Pending
		v.Pending = &ProposalView{From: pr.From, To: pr.To,
			GiveHand:   append([]Bean{}, pr.GiveHand...),
			GiveFaceUp: append([]Bean{}, pr.GiveFaceUp...),
			GetHand:    append([]Bean{}, pr.GetHand...)}
	}
	if s.Over() {
		v.Scores = s.Scores()
	}

//line bohnanza.w:1201
	return v
}

//line bohnanza.w:1220
func (s *State) playerView(i int, p *Player, viewer int) PlayerView {
	pv := PlayerView{
		Index:     i,
		IsYou:     i == viewer,
		Coins:     p.Coins(),
		HandCount: len(p.Hand),
		Acquired:  append([]Bean{}, p.Acquired...),
	}
	for _, f := range p.Fields {
		pv.Fields = append(pv.Fields, FieldView{Crop: f.Crop, Count: f.Count})
	}
	if i == viewer {
		pv.Hand = append([]Bean{}, p.Hand...)
	}
	return pv
}

//line bohnanza.w:1239
func (s *State) ViewJSON(player int) ([]byte, error) {
	return json.Marshal(s.View(player))
}

//line bohnanza.w:1246
type BeanInfoView struct {
	ID    Bean   `json:"id"`
	Name  string `json:"name"`
	Count int    `json:"count"`
	Meter [4]int `json:"meter"`
}

func Catalog() []BeanInfoView {
	out := make([]BeanInfoView, 0, NumBeans)
	for b := Bean(0); b < NumBeans; b++ {
		info := beanTable[b]
		out = append(out, BeanInfoView{b, info.Name, info.Count, info.Meter})
	}
	return out
}
