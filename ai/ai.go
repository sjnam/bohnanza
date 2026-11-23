//line ai/ai.gw:38
package ai

import (
	"fmt"
	"math/rand/v2"

	bz "github.com/sjnam/bohnanza/engine"
)

//line ai/ai.gw:67
type Policy interface {
	Act(v bz.View, rng *rand.Rand) bz.Action
}

//line ai/ai.gw:74
type Random struct{}

func (Random) Act(v bz.View, rng *rand.Rand) bz.Action {
	return v.Legal[rng.IntN(len(v.Legal))]
}

//line ai/ai.gw:85
type Greedy struct {
	trade  bool
	budget int
}

func NewGreedy() *Greedy { return &Greedy{trade: true} }

//line ai/ai.gw:91
func NewCautious() *Greedy { return &Greedy{trade: false} }

//line ai/ai.gw:97
func (g *Greedy) Act(v bz.View, rng *rand.Rand) bz.Action {
	switch v.Stage {
	case bz.PhasePlant:
		g.budget = 2 * len(v.Players)
		return plantMove(v)
	case bz.PhaseTrade:
		if v.Pending != nil {
			return respondMove(v)
		}
		return g.tradeMove(v)
	case bz.PhaseHarvestGifts:
		return giftMove(v)
	case bz.PhaseOffer:
		return offerMove(v)
	case bz.PhaseDuelDraw:
		return duelDrawMove(v)
	}
	return v.Legal[0]
}

//line ai/ai.gw:126
func ripe(f bz.FieldView) bool {
	if f.Count == 0 {
		return false
	}
	c := f.Crop.Coins(f.Count)
	return c >= 1 && c == f.Crop.Coins(f.Count+50)
}

//line ai/ai.gw:138
func bestField(me bz.PlayerView, b bz.Bean) (int, bool) {
	best := -1
	for i, f := range me.Fields {
		if f.Count > 0 && f.Crop == b {
			if best < 0 || f.Count > me.Fields[best].Count {
				best = i
			}
		}
	}
	if best >= 0 {
		return best, true
	}
	for i, f := range me.Fields {
		if f.Count == 0 {
			return i, true
		}
	}
	return -1, false
}

//line ai/ai.gw:163
func bestHarvest(v bz.View) (bz.Action, bool) {
	me := v.Players[v.You]
	var best bz.Action
	bc, bn, ok := -1, -1, false
	for _, a := range v.Legal {
		if a.Kind != bz.Harvest {
			continue
		}
		f := me.Fields[a.FieldNo]
		c := f.Crop.Coins(f.Count)
		if c > bc || (c == bc && f.Count > bn) {
			best, bc, bn, ok = a, c, f.Count, true
		}
	}
	return best, ok
}

//line ai/ai.gw:186
func plantMove(v bz.View) bz.Action {
	me := v.Players[v.You]

//line ai/ai.gw:198
	if a, ok := pick(v.Legal, func(a bz.Action) bool {
		return a.Kind == bz.Harvest && ripe(me.Fields[a.FieldNo])
	}); ok {
		return a
	}

//line ai/ai.gw:189

//line ai/ai.gw:207
	if me.Coins >= 3 && len(me.Fields) == 2 {
		if a, ok := pick(v.Legal, func(a bz.Action) bool {
			return a.Kind == bz.BuyField
		}); ok {
			return a
		}
	}

//line ai/ai.gw:190

//line ai/ai.gw:221
	canEnd := hasKind(v.Legal, bz.EndPhase)
	if len(me.Hand) > 0 {
		b := me.Hand[0]
		if f, ok := bestField(me, b); ok {
			matching := me.Fields[f].Count > 0
			if canEnd && !matching {
				return endOr(v)
			}
			if a, ok := pick(v.Legal, func(a bz.Action) bool {
				return a.Kind == bz.PlantFront && a.FieldNo == f
			}); ok {
				return a
			}
		} else if !canEnd {
			if a, ok := bestHarvest(v); ok {
				return a
			}
		}
	}

//line ai/ai.gw:191
	return endOr(v)
}

//line ai/ai.gw:249
func (g *Greedy) tradeMove(v bz.View) bz.Action {
	me := v.Players[v.You]

//line ai/ai.gw:198
	if a, ok := pick(v.Legal, func(a bz.Action) bool {
		return a.Kind == bz.Harvest && ripe(me.Fields[a.FieldNo])
	}); ok {
		return a
	}

//line ai/ai.gw:252

//line ai/ai.gw:261
	if a, ok := pick(v.Legal, func(a bz.Action) bool {
		if a.Kind != bz.TakeRevealed {
			return false
		}
		f := me.Fields[a.FieldNo]
		return f.Count > 0 && f.Crop == v.FaceUp[a.FaceUpNo]
	}); ok {
		return a
	}

//line ai/ai.gw:253

//line ai/ai.gw:285
	if a, ok := pick(v.Legal, func(a bz.Action) bool {
		return a.Kind == bz.TakeRevealed && me.Fields[a.FieldNo].Count == 0
	}); ok {
		return a
	}

//line ai/ai.gw:254

//line ai/ai.gw:275
	if g.trade && g.budget > 0 {
		if a, ok := proposeTrade(v); ok {
			g.budget--
			return a
		}
	}

//line ai/ai.gw:255

//line ai/ai.gw:295
	if len(v.FaceUp) > 0 {
		if a, ok := bestHarvest(v); ok {
			return a
		}
	}

//line ai/ai.gw:256
	return endOr(v)
}

//line ai/ai.gw:308
func proposeTrade(v bz.View) (bz.Action, bool) {
	me := v.Players[v.You]
	for _, b := range v.FaceUp {
		if matchesField(me, b) {
			continue // 내가 기르는 콩이면 넘기지 않고 내가 집는다
		}
		o := wanter(v, b)
		if o < 0 {
			continue // 아무도 안 기르는 콩은 넘길 데가 없다
		}

//line ai/ai.gw:327
		if r, want := requestBean(me, v.Players[o]); want {
			return bz.Action{Kind: bz.ProposeTrade, Actor: v.You, To: o,
				GiveFaceUp: []bz.Bean{b}, GetHand: []bz.Bean{r}}, true
		}
		return bz.Action{Kind: bz.ProposeTrade, Actor: v.You, To: o,
			GiveFaceUp: []bz.Bean{b}}, true

//line ai/ai.gw:319
	}
	return bz.Action{}, false
}

//line ai/ai.gw:337
func wanter(v bz.View, b bz.Bean) int {
	for i, p := range v.Players {
		if i != v.You && matchesField(p, b) {
			return i
		}
	}
	return -1
}

//line ai/ai.gw:350
func requestBean(me, opp bz.PlayerView) (bz.Bean, bool) {
	var best bz.Bean
	bn, ok := -1, false
	for _, f := range me.Fields {
		if f.Count == 0 || ripe(f) || matchesField(opp, f.Crop) {
			continue
		}
		if f.Count > bn {
			best, bn, ok = f.Crop, f.Count, true
		}
	}
	return best, ok
}

//line ai/ai.gw:369
func respondMove(v bz.View) bz.Action {
	me := v.Players[v.You]
	accept := worthAccepting(me, v.Pending)
	if a, ok := pick(v.Legal, func(a bz.Action) bool {
		return a.Kind == bz.RespondTrade && a.Accept == accept
	}); ok {
		return a
	}
	return v.Legal[0]
}

//line ai/ai.gw:384
func worthAccepting(me bz.PlayerView, pr *bz.ProposalView) bool {
	give := pr.GetHand // 내가 손패에서 내주는 콩
	if !holds(me.Hand, give) {
		return false
	}
	gain := countMatching(me, pr.GiveHand) + countMatching(me, pr.GiveFaceUp)
	loss := countMatching(me, give)
	return gain > loss
}

//line ai/ai.gw:397
func countMatching(me bz.PlayerView, bs []bz.Bean) int {
	n := 0
	for _, b := range bs {
		if matchesField(me, b) {
			n++
		}
	}
	return n
}

//line ai/ai.gw:412
func giftMove(v bz.View) bz.Action {
	me := v.Players[v.You]

//line ai/ai.gw:198
	if a, ok := pick(v.Legal, func(a bz.Action) bool {
		return a.Kind == bz.Harvest && ripe(me.Fields[a.FieldNo])
	}); ok {
		return a
	}

//line ai/ai.gw:415
	if len(me.Acquired) > 0 {
		b := me.Acquired[0]
		if f, ok := bestField(me, b); ok {
			if a, ok := pick(v.Legal, func(a bz.Action) bool {
				return a.Kind == bz.PlantGift && a.FieldNo == f
			}); ok {
				return a
			}
		}
	}
	if a, ok := bestHarvest(v); ok {
		return a
	}
	return v.Legal[0]
}

//line ai/ai.gw:442
func offerMove(v bz.View) bz.Action {
	me := v.Players[v.You]

//line ai/ai.gw:198
	if a, ok := pick(v.Legal, func(a bz.Action) bool {
		return a.Kind == bz.Harvest && ripe(me.Fields[a.FieldNo])
	}); ok {
		return a
	}

//line ai/ai.gw:445

//line ai/ai.gw:261
	if a, ok := pick(v.Legal, func(a bz.Action) bool {
		if a.Kind != bz.TakeRevealed {
			return false
		}
		f := me.Fields[a.FieldNo]
		return f.Count > 0 && f.Crop == v.FaceUp[a.FaceUpNo]
	}); ok {
		return a
	}

//line ai/ai.gw:446

//line ai/ai.gw:285
	if a, ok := pick(v.Legal, func(a bz.Action) bool {
		return a.Kind == bz.TakeRevealed && me.Fields[a.FieldNo].Count == 0
	}); ok {
		return a
	}

//line ai/ai.gw:447

//line ai/ai.gw:452
	if a, ok := pick(v.Legal, func(a bz.Action) bool {
		return a.Kind == bz.TossRevealed
	}); ok {
		return a
	}

//line ai/ai.gw:448
	return v.Legal[0]
}

//line ai/ai.gw:464
func duelDrawMove(v bz.View) bz.Action {
	me := v.Players[v.You]

//line ai/ai.gw:198
	if a, ok := pick(v.Legal, func(a bz.Action) bool {
		return a.Kind == bz.Harvest && ripe(me.Fields[a.FieldNo])
	}); ok {
		return a
	}

//line ai/ai.gw:467

//line ai/ai.gw:261
	if a, ok := pick(v.Legal, func(a bz.Action) bool {
		if a.Kind != bz.TakeRevealed {
			return false
		}
		f := me.Fields[a.FieldNo]
		return f.Count > 0 && f.Crop == v.FaceUp[a.FaceUpNo]
	}); ok {
		return a
	}

//line ai/ai.gw:468
	return endOr(v)
}

//line ai/ai.gw:488
func step(b bz.Bean, n int) float64 {
	need := nextNeed(b, n)
	if need == 0 {
		return 0 // 익은 밭: 더 심어도 안 오른다
	}
	return float64(b.Coins(need)-b.Coins(n)) / float64(need-n)
}

//line ai/ai.gw:499
func nextNeed(b bz.Bean, n int) int {
	for k := n + 1; k <= n+24; k++ {
		if b.Coins(k) > b.Coins(n) {
			return k
		}
	}
	return 0
}

//line ai/ai.gw:513
const newFieldRate = 0.5 // 빈 밭을 새로 여는 값어치는 반만 친다

func valueTo(p bz.PlayerView, b bz.Bean) float64 {
	best, empty := 0.0, false
	for _, f := range p.Fields {
		if f.Count == 0 {
			empty = true
		} else if f.Crop == b {
			if s := step(b, f.Count); s > best {
				best = s
			}
		}
	}
	if best > 0 {
		return best
	}
	if empty {
		return step(b, 0) * newFieldRate
	}
	return 0
}

//line ai/ai.gw:539
func standing(p bz.PlayerView) int {
	n := p.Coins
	for _, f := range p.Fields {
		n += f.Crop.Coins(f.Count)
	}
	return n
}

func leader(v bz.View) int {
	best, top := -1, -1
	for i, p := range v.Players {
		if s := standing(p); s > top {
			best, top = i, s
		}
	}
	return best
}

//line ai/ai.gw:562
type Strategist struct {
	budget int
}

func NewStrategist() *Strategist { return &Strategist{} }

func (g *Strategist) Act(v bz.View, rng *rand.Rand) bz.Action {
	switch v.Stage {
	case bz.PhasePlant:
		g.budget = 2 * len(v.Players)
		return plantMove(v)
	case bz.PhaseTrade:
		if v.Pending != nil {
			return respondStrategic(v)
		}
		return g.tradeMove(v)
	case bz.PhaseHarvestGifts:
		return giftMove(v)
	case bz.PhaseOffer:
		return offerMove(v)
	case bz.PhaseDuelDraw:
		return duelDrawMove(v)
	}
	return v.Legal[0]
}

//line ai/ai.gw:593
func (g *Strategist) tradeMove(v bz.View) bz.Action {
	me := v.Players[v.You]

//line ai/ai.gw:198
	if a, ok := pick(v.Legal, func(a bz.Action) bool {
		return a.Kind == bz.Harvest && ripe(me.Fields[a.FieldNo])
	}); ok {
		return a
	}

//line ai/ai.gw:596

//line ai/ai.gw:261
	if a, ok := pick(v.Legal, func(a bz.Action) bool {
		if a.Kind != bz.TakeRevealed {
			return false
		}
		f := me.Fields[a.FieldNo]
		return f.Count > 0 && f.Crop == v.FaceUp[a.FaceUpNo]
	}); ok {
		return a
	}

//line ai/ai.gw:597

//line ai/ai.gw:285
	if a, ok := pick(v.Legal, func(a bz.Action) bool {
		return a.Kind == bz.TakeRevealed && me.Fields[a.FieldNo].Count == 0
	}); ok {
		return a
	}

//line ai/ai.gw:598
	if g.budget > 0 {
		if a, ok := planTrade(v); ok {
			g.budget--
			return a
		}
	}

//line ai/ai.gw:295
	if len(v.FaceUp) > 0 {
		if a, ok := bestHarvest(v); ok {
			return a
		}
	}

//line ai/ai.gw:605
	return endOr(v)
}

//line ai/ai.gw:625
func planTrade(v bz.View) (bz.Action, bool) {
	me, lead := v.Players[v.You], leader(v)
	var best bz.Action
	top, ok := 0.0, false
	for _, b := range v.FaceUp {
		if matchesField(me, b) {
			continue // 내가 기르는 콩이면 넘기지 않고 내가 집는다
		}
		for o := range v.Players {

//line ai/ai.gw:645
			if o == v.You || !matchesField(v.Players[o], b) {
				continue
			}
			gain := 0.0
			r, want := askBean(me, v.Players[o])
			if want {
				gain = valueTo(me, r)
			}
			cost := valueTo(v.Players[o], b)
			if o == lead {
				cost *= 2
			}
			if edge := gain - cost; edge >= 0 && (!ok || edge > top) {
				best, top, ok = tradeAction(v.You, o, b, r, want), edge, true
			}

//line ai/ai.gw:635
		}
	}
	return best, ok
}

//line ai/ai.gw:664
func tradeAction(me, to int, give, get bz.Bean, want bool) bz.Action {
	a := bz.Action{Kind: bz.ProposeTrade, Actor: me, To: to,
		GiveFaceUp: []bz.Bean{give}}
	if want {
		a.GetHand = []bz.Bean{get}
	}
	return a
}

//line ai/ai.gw:678
func askBean(me, opp bz.PlayerView) (bz.Bean, bool) {
	var best bz.Bean
	top, ok := 0.0, false
	for _, f := range me.Fields {
		if f.Count == 0 || matchesField(opp, f.Crop) {
			continue
		}
		if s := step(f.Crop, f.Count); s > top {
			best, top, ok = f.Crop, s, true
		}
	}
	return best, ok
}

//line ai/ai.gw:697
func respondStrategic(v bz.View) bz.Action {
	yes := worthIt(v)
	if a, ok := pick(v.Legal, func(a bz.Action) bool {
		return a.Kind == bz.RespondTrade && a.Accept == yes
	}); ok {
		return a
	}
	return v.Legal[0]
}

//line ai/ai.gw:719
func worthIt(v bz.View) bool {
	me, pr := v.Players[v.You], v.Pending
	if !holds(me.Hand, pr.GetHand) {
		return false
	}
	from := v.Players[pr.From]
	mine := sumValue(me, pr.GiveHand) + sumValue(me, pr.GiveFaceUp) -
		sumValue(me, pr.GetHand)
	theirs := sumValue(from, pr.GetHand) - sumValue(from, pr.GiveHand)
	if theirs > 0 && pr.From == leader(v) {
		theirs *= 2
	}
	return mine > 0 && mine >= theirs
}

//line ai/ai.gw:735
func sumValue(p bz.PlayerView, bs []bz.Bean) float64 {
	t := 0.0
	for _, b := range bs {
		t += valueTo(p, b)
	}
	return t
}

//line ai/ai.gw:747
func pick(legal []bz.Action, want func(bz.Action) bool) (bz.Action, bool) {
	for _, a := range legal {
		if want(a) {
			return a, true
		}
	}
	return bz.Action{}, false
}

func hasKind(legal []bz.Action, k bz.ActionKind) bool {
	_, ok := pick(legal, func(a bz.Action) bool { return a.Kind == k })
	return ok
}

//line ai/ai.gw:764
func endOr(v bz.View) bz.Action {
	if a, ok := pick(v.Legal, func(a bz.Action) bool {
		return a.Kind == bz.EndPhase
	}); ok {
		return a
	}
	return v.Legal[0]
}

//line ai/ai.gw:776
func matchesField(me bz.PlayerView, b bz.Bean) bool {
	for _, f := range me.Fields {
		if f.Count > 0 && f.Crop == b {
			return true
		}
	}
	return false
}

//line ai/ai.gw:788
func holds(pool, want []bz.Bean) bool {
	cnt := make(map[bz.Bean]int)
	for _, b := range pool {
		cnt[b]++
	}
	for _, b := range want {
		cnt[b]--
		if cnt[b] < 0 {
			return false
		}
	}
	return true
}

// 한 판에 드는 수의 상한. 2인부터 4인까지 실측 최대가 800수 남짓이니 넉넉하다.
//
//line ai/ai.gw:808
//line ai/ai.gw:809
const maxSteps = 100000

func Play(ps []Policy, seed uint64) ([]int, error) {
	s, err := bz.New(len(ps), seed)
	if err != nil {
		return nil, err
	}
	rng := rand.New(rand.NewPCG(seed, 0x1234567))
	step := 0
	for ; step < maxSteps && !s.Over(); step++ {
		actor := s.ToAct()
		if actor < 0 {
			break
		}
		a := ps[actor].Act(s.View(actor), rng)
		if _, err := s.Apply(a); err != nil {
			return nil, fmt.Errorf("봇 %d의 수 적용 실패(씨앗 %d): %w", actor, seed, err)
		}
	}

//line ai/ai.gw:837
	if !s.Over() {
		return nil, fmt.Errorf("판이 %d수에서 끝나지 않음(씨앗 %d, 단계 %v)",
			step, seed, s.Stage)
	}

//line ai/ai.gw:829
	return s.Scores(), nil
}
