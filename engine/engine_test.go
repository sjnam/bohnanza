//line engine/engine.w:1623
package engine

import (
	"bytes"
	"encoding/json"
	"math/rand/v2"
	"testing"
)

//line engine/engine.w:1645
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

//line engine/engine.w:1665
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

//line engine/engine.w:1687
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

//line engine/engine.w:1712
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

//line engine/engine.w:1707
}

//line engine/engine.w:1732
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

//line engine/engine.w:1764
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

//line engine/engine.w:1796
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

//line engine/engine.w:1820
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

//line engine/engine.w:1815
}

//line engine/engine.w:1849
func TestSpectatorSeesNoHands(t *testing.T) {
	s, err := New(3, 7)
	if err != nil {
		t.Fatal(err)
	}
	v := s.View(Spectator)

//line engine/engine.w:1860
	for i, p := range v.Players {
		if p.Hand != nil {
			t.Errorf("관전자에게 %d번 손패가 새어 나감: %v", i, p.Hand)
		}
		if p.IsYou {
			t.Errorf("관전자가 %d번을 제 자리로 앎", i)
		}
	}
	if v.Legal != nil {
		t.Errorf("관전자에게 둘 수 있는 수가 생김: %v", v.Legal)
	}
	if v.You != Spectator {
		t.Errorf("관전자의 You가 %d", v.You)
	}

//line engine/engine.w:1856

//line engine/engine.w:1879
	if len(v.Players) != 3 || v.DeckCount != len(s.Deck) {
		t.Errorf("관전자가 공개 정보를 못 봄: %d명, 덱 %d", len(v.Players), v.DeckCount)
	}
	for i, p := range v.Players {
		if p.HandCount != StartingHand {
			t.Errorf("관전자가 %d번 손패 장수를 못 봄: %d", i, p.HandCount)
		}
	}
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(b, []byte(`"hand"`)) {
		t.Errorf("관전자 JSON에 hand 칸이 실림: %s", b)
	}

//line engine/engine.w:1857
}

//line engine/engine.w:1899
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

//line engine/engine.w:1927
func TestVariantSetup(t *testing.T) {
	cases := []struct{ players, deck, removed, fields int }{
		{2, 144 - 10, 10, 3}, // 정원콩 6 + 카카오콩 4
		{3, 150 - 15, 4, 3},  // 카카오콩 4
		{4, 130 - 20, 24, 2}, // 커피콩 24
		{5, 130 - 25, 24, 2}, // 커피콩 24
		{6, 144 - 30, 10, 2}, // 카카오콩 4 + 정원콩 6
		{7, 144 - 35, 10, 2}, // 카카오콩 4 + 정원콩 6
	}
	for _, c := range cases {
		s, err := New(c.players, 7)
		if err != nil {
			t.Fatal(err)
		}

//line engine/engine.w:1948
		if len(s.Deck) != c.deck {
			t.Errorf("%d인: 덱 %d장, %d장 기대", c.players, len(s.Deck), c.deck)
		}
		if len(s.Removed) != c.removed {
			t.Errorf("%d인: 뺀 콩 %d장, %d장 기대", c.players, len(s.Removed), c.removed)
		}
		if n := len(s.Players[0].Fields); n != c.fields {
			t.Errorf("%d인: 밭 %d칸, %d칸 기대", c.players, n, c.fields)
		}
		if err := s.Check(); err != nil {
			t.Errorf("%d인: %v", c.players, err)
		}
		for _, p := range s.Players {
			for _, b := range p.Hand {
				if s.Rules.drops(b) {
					t.Errorf("%d인: 뺀 %s이 손패에 있음", c.players, b.Name())
				}
			}
		}

//line engine/engine.w:1942
	}
}

//line engine/engine.w:1971
func TestFieldBuyingByVariant(t *testing.T) {
	for _, c := range []struct {
		players int
		want    bool
	}{{2, false}, {3, false}, {4, true}, {5, true}, {6, true}, {7, true}} {
		s, _ := New(c.players, 5)
		s.Players[0].Treasury = []Card{Red, Red, Red}
		got := false
		for _, a := range s.Legal(0) {
			if a.Kind == BuyField {
				got = true
			}
		}
		if got != c.want {
			t.Errorf("%d인: 밭 사기 %v, %v 기대", c.players, got, c.want)
		}
	}
}

//line engine/engine.w:1993
func TestRefillByVariant(t *testing.T) {
	for _, n := range []int{3, 4, 5, 6, 7} {
		s, _ := New(n, 5)
		before := handSizes(s)
		s.endTurn()
		for i, p := range s.Players {
			if len(p.Hand) != before[i]+1 {
				t.Errorf("%d인 %d번: %d→%d장, 전원 한 장씩 기대",
					n, i, before[i], len(p.Hand))
			}
		}
	}

//line engine/engine.w:2009
	s2, _ := New(2, 5)
	was := handSizes(s2)
	s2.endTurn()
	for i, p := range s2.Players {
		want := was[i]
		if i == 0 {
			want += 2
		}
		if len(p.Hand) != want {
			t.Errorf("2인 %d번: %d장, %d장 기대", i, len(p.Hand), want)
		}
	}

//line engine/engine.w:2006
}

//line engine/engine.w:2023
func handSizes(s *State) []int {
	n := make([]int, len(s.Players))
	for i, p := range s.Players {
		n[i] = len(p.Hand)
	}
	return n
}

//line engine/engine.w:2034
func TestDuelTossHand(t *testing.T) {
	s, _ := New(2, 11)
	p := s.Players[0]
	if _, err := s.Apply(Action{Kind: PlantFront, Actor: 0, FieldNo: 0}); err != nil {
		t.Fatal(err) // 한 장 심어야 버릴 수 있다
	}

//line engine/engine.w:2045
	tosses := 0
	for _, a := range s.Legal(0) {
		if a.Kind == TossHand {
			tosses++
		}
	}
	if tosses != len(p.Hand) {
		t.Errorf("버리기 수 %d개, 손패 %d장", tosses, len(p.Hand))
	}

//line engine/engine.w:2041

//line engine/engine.w:2056
	want, size := p.Hand[2], len(p.Hand)
	ev, err := s.Apply(Action{Kind: TossHand, Actor: 0, HandNo: 2})
	if err != nil {
		t.Fatal(err)
	}
	if ev[0].Kind != Tossed || ev[0].Crop != want {
		t.Errorf("이벤트가 어긋남: %v", ev[0])
	}
	if s.Discard[len(s.Discard)-1] != want {
		t.Error("버린 콩이 버림 더미에 없음")
	}
	if len(p.Hand) != size-1 {
		t.Errorf("손패가 %d장", len(p.Hand))
	}
	if _, err := s.Apply(Action{Kind: TossHand, Actor: 0, HandNo: 0}); err == nil {
		t.Error("한 턴에 두 장을 버렸는데 통과함")
	}
	if err := s.Check(); err != nil {
		t.Error(err)
	}

//line engine/engine.w:2042
}

//line engine/engine.w:2082
func TestDuelTurnFlow(t *testing.T) {
	s, _ := New(2, 3)
	if s.Stage != PhasePlant {
		t.Fatalf("시작 단계가 %v, 시작 플레이어는 제안을 건너뛰어야 함", s.Stage)
	}
	mustApply(t, s, Action{Kind: PlantFront, Actor: 0, FieldNo: 0})
	mustApply(t, s, Action{Kind: EndPhase, Actor: 0})

//line engine/engine.w:2094
	if s.Stage != PhaseDuelDraw {
		t.Fatalf("단계가 %v, 뽑아 나누기 기대", s.Stage)
	}
	if len(s.FaceUp) < 3 {
		t.Fatalf("상 위에 %d장, 적어도 3장 기대", len(s.FaceUp))
	}

//line engine/engine.w:2090

//line engine/engine.w:2102
	left := append([]Card{}, s.FaceUp...)
	mustApply(t, s, Action{Kind: EndPhase, Actor: 0})
	if s.Active != 1 {
		t.Errorf("차례가 %d번", s.Active)
	}
	if s.Stage != PhaseOffer {
		t.Errorf("단계가 %v, 받은 제안 기대", s.Stage)
	}
	if !containsAll(s.FaceUp, left) || len(s.FaceUp) != len(left) {
		t.Errorf("남긴 콩이 바뀜: %v → %v", left, s.FaceUp)
	}
	if err := s.Check(); err != nil {
		t.Error(err)
	}

//line engine/engine.w:2091
}

//line engine/engine.w:2118
func mustApply(t *testing.T, s *State, a Action) {
	t.Helper()
	if _, err := s.Apply(a); err != nil {
		t.Fatalf("%v: %v", a, err)
	}
}

//line engine/engine.w:2129
func TestRandomPlaythrough(t *testing.T) {
	for seed := uint64(0); seed < 200; seed++ {
		players := 2 + int(seed%6) // 2~7인을 고루 훑는다
		s, err := New(players, seed)
		if err != nil {
			t.Fatal(err)
		}
		rng := rand.New(rand.NewPCG(seed, 12345))

//line engine/engine.w:2144
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

//line engine/engine.w:2138
	}
}
