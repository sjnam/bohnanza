//line bohnanza.w:1143
package bohnanza

import (
	"encoding/json"
	"math/rand/v2"
	"testing"
)

//line bohnanza.w:1161
func TestDeckSize(t *testing.T) {
	total := 0
	for b := Bean(0); b < NumBeans; b++ {
		total += beanTable[b].Count
	}
	if total != TotalCards {
		t.Fatalf("콩미터 장수 합 %d, 154 기대", total)
	}
	s, err := New(4, 1)
	if err != nil {
		t.Fatal(err)
	}
	if err := s.Check(); err != nil {
		t.Fatal(err)
	}
}

//line bohnanza.w:1181
func TestCoins(t *testing.T) {
	cases := []struct {
		b    Bean
		n    int
		want int
	}{
		{Coffee, 3, 0}, {Coffee, 4, 1}, {Coffee, 12, 4}, {Coffee, 20, 4},
		{Cocoa, 1, 0}, {Cocoa, 2, 2}, {Cocoa, 4, 4},
		{Red, 2, 1}, {Red, 5, 4},
	}
	for _, c := range cases {
		if got := c.b.Coins(c.n); got != c.want {
			t.Errorf("%s %d장: 코인 %d, %d 기대", c.b.Name(), c.n, got, c.want)
		}
	}
}

//line bohnanza.w:1203
func TestBilateralTrade(t *testing.T) {
	s := &State{
		Players: []*Player{
			{Hand: []Card{Coffee, Blue}, Fields: make([]Field, 2)},
			{Hand: []Card{Red}, Fields: make([]Field, 2)},
		},
		Stage:  PhaseTrade,
		Active: 0,
	}
	if _, err := s.Apply(Action{Kind: ProposeTrade, Actor: 0, To: 1,
		GiveHand: []Card{Coffee}, GetHand: []Card{Red}}); err != nil {
		t.Fatal(err)
	}
	if s.ToAct() != 1 {
		t.Fatalf("제안 뒤에는 1번이 응답해야 함, ToAct=%d", s.ToAct())
	}
	if _, err := s.Apply(Action{Kind: RespondTrade, Actor: 1, Accept: true}); err != nil {
		t.Fatal(err)
	}

//line bohnanza.w:1228
	p0, p1 := s.Players[0], s.Players[1]
	if len(p0.Acquired) != 1 || p0.Acquired[0] != Red {
		t.Errorf("0번 받은 콩이 강낭콩이 아님: %v", p0.Acquired)
	}
	if len(p1.Acquired) != 1 || p1.Acquired[0] != Coffee {
		t.Errorf("1번 받은 콩이 커피콩이 아님: %v", p1.Acquired)
	}
	if len(p0.Hand) != 1 || p0.Hand[0] != Blue {
		t.Errorf("0번 손패가 잘못됨: %v", p0.Hand)
	}
	if len(p1.Hand) != 0 {
		t.Errorf("1번 손패가 비어야 함: %v", p1.Hand)
	}
	if s.Pending != nil {
		t.Error("교환 뒤에도 대기 제안이 남음")
	}

//line bohnanza.w:1223
}

//line bohnanza.w:1248
func TestMultiCardTrade(t *testing.T) {
	s := &State{
		Players: []*Player{
			{Hand: []Card{Coffee, Coffee, Blue}, Fields: make([]Field, 2)},
			{Hand: []Card{Red, Chili}, Fields: make([]Field, 2)},
		},
		Stage:  PhaseTrade,
		Active: 0,
	}
	if _, err := s.Apply(Action{Kind: ProposeTrade, Actor: 0, To: 1,
		GiveHand: []Card{Coffee, Coffee}, GetHand: []Card{Red, Chili}}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Apply(Action{Kind: RespondTrade, Actor: 1, Accept: true}); err != nil {
		t.Fatal(err)
	}
	p0, p1 := s.Players[0], s.Players[1]
	if len(p0.Acquired) != 2 || len(p1.Acquired) != 2 {
		t.Errorf("받은 콩 수가 틀림: 0=%v 1=%v", p0.Acquired, p1.Acquired)
	}
	if len(p0.Hand) != 1 || p0.Hand[0] != Blue {
		t.Errorf("0번 손패가 틀림: %v", p0.Hand)
	}
	if len(p1.Hand) != 0 {
		t.Errorf("1번 손패가 비어야 함: %v", p1.Hand)
	}
}

//line bohnanza.w:1280
func TestProposeNeedsFulfillment(t *testing.T) {
	s := &State{
		Players: []*Player{
			{Hand: []Card{Coffee}, Fields: make([]Field, 2)},
			{Hand: []Card{Red}, Fields: make([]Field, 2)},
		},
		Stage:  PhaseTrade,
		Active: 0,
	}
	if _, err := s.Apply(Action{Kind: ProposeTrade, Actor: 0, To: 1,
		GiveHand: []Card{Coffee}, GetHand: []Card{Blue}}); err != nil {
		t.Fatalf("제안 자체는 통과해야 함: %v", err)
	}
	if _, err := s.Apply(Action{Kind: RespondTrade, Actor: 1, Accept: true}); err == nil {
		t.Error("없는 콩을 요구한 제안의 수락은 실패해야 함")
	}
	if s.Pending == nil {
		t.Error("실패한 수락은 제안을 그대로 남겨야 함")
	}
	if _, err := s.Apply(Action{Kind: RespondTrade, Actor: 1, Accept: false}); err != nil {
		t.Fatalf("거절은 되어야 함: %v", err)
	}
	if s.Pending != nil || s.ToAct() != 0 {
		t.Error("거절 뒤 제안이 사라지고 차례가 제안자에게 돌아와야 함")
	}
}

//line bohnanza.w:1312
func TestViewRedaction(t *testing.T) {
	s, err := New(3, 7)
	if err != nil {
		t.Fatal(err)
	}
	v := s.View(0)
	if len(v.Players[0].Hand) != StartingHand || !v.Players[0].IsYou {
		t.Errorf("내 손패는 카드까지 보여야 함: %v", v.Players[0])
	}
	if v.Players[1].Hand != nil {
		t.Errorf("남의 손패 카드가 노출됨: %v", v.Players[1].Hand)
	}
	if v.Players[1].HandCount != StartingHand {
		t.Errorf("남의 손패 장수가 틀림: %d", v.Players[1].HandCount)
	}
	if v.DeckCount != len(s.Deck) {
		t.Errorf("덱 장수가 틀림: %d", v.DeckCount)
	}

//line bohnanza.w:1336
	b, err := s.ViewJSON(0)
	if err != nil {
		t.Fatal(err)
	}
	var back View
	if err := json.Unmarshal(b, &back); err != nil {
		t.Fatal(err)
	}
	if len(back.Players[1].Hand) != 0 {
		t.Errorf("JSON에 남의 손패가 새어 나감: %v", back.Players[1].Hand)
	}
	if !back.Players[0].IsYou {
		t.Errorf("JSON 왕복 뒤 IsYou가 사라짐")
	}
	cat := Catalog()
	total := 0
	for _, e := range cat {
		total += e.Count
	}
	if len(cat) != int(NumBeans) || total != TotalCards {
		t.Errorf("도감이 이상함: %d종 %d장", len(cat), total)
	}

//line bohnanza.w:1331
}

//line bohnanza.w:1363
func TestHarvestRestriction(t *testing.T) {
	s := &State{
		Players: []*Player{{Fields: []Field{{Coffee, 1}, {Blue, 2}}}},
		Stage:   PhasePlant,
	}
	p := s.Players[0]
	if p.canHarvest(0) {
		t.Error("다른 밭에 두 장 있으니 한 장짜리 0번 밭은 못 거둬야 함")
	}
	if !p.canHarvest(1) {
		t.Error("두 장짜리 1번 밭은 거둘 수 있어야 함")
	}
	if _, err := s.harvest(p, 1); err != nil {
		t.Fatal(err)
	}
	if !p.canHarvest(0) {
		t.Error("두 장 이상인 밭이 없으니 한 장짜리 0번 밭도 거둘 수 있어야 함")
	}
	q := &Player{Fields: []Field{{Coffee, 1}, {Blue, 1}}}
	if !q.canHarvest(0) || !q.canHarvest(1) {
		t.Error("모든 밭이 한 장이면 어느 밭이든 거둘 수 있어야 함")
	}
}

//line bohnanza.w:1391
func TestRandomPlaythrough(t *testing.T) {
	for seed := uint64(0); seed < 200; seed++ {
		players := 2 + int(seed%3)
		s, err := New(players, seed)
		if err != nil {
			t.Fatal(err)
		}
		rng := rand.New(rand.NewPCG(seed, 12345))

//line bohnanza.w:1406
		for step := 0; step < 100000 && !s.Over(); step++ {
			actor := s.ToAct()
			if actor < 0 {
				t.Fatalf("씨앗 %d: 둘 사람이 없는데 게임이 안 끝남", seed)
			}
			acts := s.Legal(actor)
			if len(acts) == 0 {
				t.Fatalf("씨앗 %d: %d단계에서 합법수가 없음", seed, s.Stage)
			}
			if _, err := s.Apply(acts[rng.IntN(len(acts))]); err != nil {
				t.Fatalf("씨앗 %d: 합법수 적용 실패: %v", seed, err)
			}
			if err := s.Check(); err != nil {
				t.Fatalf("씨앗 %d, %d수째: %v", seed, step, err)
			}
		}
		if !s.Over() {
			t.Fatalf("씨앗 %d: 10만 수 안에 게임이 안 끝남", seed)
		}

//line bohnanza.w:1400
	}
}
