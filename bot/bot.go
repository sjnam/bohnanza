//line bot/bot.w:31
package bot

import (
	"fmt"
	"math/rand/v2"

	bz "github.com/sjnam/bohnanza"
)

//line bot/bot.w:58
type Policy interface {
	Act(v bz.View, rng *rand.Rand) bz.Action
}

//line bot/bot.w:65
type Random struct{}

func (Random) Act(v bz.View, rng *rand.Rand) bz.Action {
	return v.Legal[rng.IntN(len(v.Legal))]
}

//line bot/bot.w:76
type Greedy struct {
	trade  bool
	budget int
}

func NewGreedy() *Greedy { return &Greedy{trade: true} }

//line bot/bot.w:82
func NewCautious() *Greedy { return &Greedy{trade: false} }

//line bot/bot.w:88
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

//line bot/bot.w:117
func ripe(f bz.FieldView) bool {
	if f.Count == 0 {
		return false
	}
	c := f.Crop.Coins(f.Count)
	return c >= 1 && c == f.Crop.Coins(f.Count+50)
}

//line bot/bot.w:129
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

//line bot/bot.w:154
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

//line bot/bot.w:177
func plantMove(v bz.View) bz.Action {
	me := v.Players[v.You]

//line bot/bot.w:189
	if a, ok := pick(v.Legal, func(a bz.Action) bool {
		return a.Kind == bz.Harvest && ripe(me.Fields[a.FieldNo])
	}); ok {
		return a
	}

//line bot/bot.w:180

//line bot/bot.w:198
	if me.Coins >= 3 && len(me.Fields) == 2 {
		if a, ok := pick(v.Legal, func(a bz.Action) bool {
			return a.Kind == bz.BuyField
		}); ok {
			return a
		}
	}

//line bot/bot.w:181

//line bot/bot.w:212
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

//line bot/bot.w:182
	return endOr(v)
}

//line bot/bot.w:240
func (g *Greedy) tradeMove(v bz.View) bz.Action {
	me := v.Players[v.You]

//line bot/bot.w:189
	if a, ok := pick(v.Legal, func(a bz.Action) bool {
		return a.Kind == bz.Harvest && ripe(me.Fields[a.FieldNo])
	}); ok {
		return a
	}

//line bot/bot.w:243

//line bot/bot.w:252
	if a, ok := pick(v.Legal, func(a bz.Action) bool {
		if a.Kind != bz.TakeRevealed {
			return false
		}
		f := me.Fields[a.FieldNo]
		return f.Count > 0 && f.Crop == v.FaceUp[a.FaceUpNo]
	}); ok {
		return a
	}

//line bot/bot.w:244

//line bot/bot.w:276
	if a, ok := pick(v.Legal, func(a bz.Action) bool {
		return a.Kind == bz.TakeRevealed && me.Fields[a.FieldNo].Count == 0
	}); ok {
		return a
	}

//line bot/bot.w:245

//line bot/bot.w:266
	if g.trade && g.budget > 0 {
		if a, ok := proposeTrade(v); ok {
			g.budget--
			return a
		}
	}

//line bot/bot.w:246

//line bot/bot.w:286
	if len(v.FaceUp) > 0 {
		if a, ok := bestHarvest(v); ok {
			return a
		}
	}

//line bot/bot.w:247
	return endOr(v)
}

//line bot/bot.w:299
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

//line bot/bot.w:318
		if r, want := requestBean(me, v.Players[o]); want {
			return bz.Action{Kind: bz.ProposeTrade, Actor: v.You, To: o,
				GiveFaceUp: []bz.Bean{b}, GetHand: []bz.Bean{r}}, true
		}
		return bz.Action{Kind: bz.ProposeTrade, Actor: v.You, To: o,
			GiveFaceUp: []bz.Bean{b}}, true

//line bot/bot.w:310
	}
	return bz.Action{}, false
}

//line bot/bot.w:328
func wanter(v bz.View, b bz.Bean) int {
	for i, p := range v.Players {
		if i != v.You && matchesField(p, b) {
			return i
		}
	}
	return -1
}

//line bot/bot.w:341
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

//line bot/bot.w:360
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

//line bot/bot.w:375
func worthAccepting(me bz.PlayerView, pr *bz.ProposalView) bool {
	give := pr.GetHand // 내가 손패에서 내주는 콩
	if !holds(me.Hand, give) {
		return false
	}
	gain := countMatching(me, pr.GiveHand) + countMatching(me, pr.GiveFaceUp)
	loss := countMatching(me, give)
	return gain > loss
}

//line bot/bot.w:388
func countMatching(me bz.PlayerView, bs []bz.Bean) int {
	n := 0
	for _, b := range bs {
		if matchesField(me, b) {
			n++
		}
	}
	return n
}

//line bot/bot.w:403
func giftMove(v bz.View) bz.Action {
	me := v.Players[v.You]

//line bot/bot.w:189
	if a, ok := pick(v.Legal, func(a bz.Action) bool {
		return a.Kind == bz.Harvest && ripe(me.Fields[a.FieldNo])
	}); ok {
		return a
	}

//line bot/bot.w:406
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

//line bot/bot.w:433
func offerMove(v bz.View) bz.Action {
	me := v.Players[v.You]

//line bot/bot.w:189
	if a, ok := pick(v.Legal, func(a bz.Action) bool {
		return a.Kind == bz.Harvest && ripe(me.Fields[a.FieldNo])
	}); ok {
		return a
	}

//line bot/bot.w:436

//line bot/bot.w:252
	if a, ok := pick(v.Legal, func(a bz.Action) bool {
		if a.Kind != bz.TakeRevealed {
			return false
		}
		f := me.Fields[a.FieldNo]
		return f.Count > 0 && f.Crop == v.FaceUp[a.FaceUpNo]
	}); ok {
		return a
	}

//line bot/bot.w:437

//line bot/bot.w:276
	if a, ok := pick(v.Legal, func(a bz.Action) bool {
		return a.Kind == bz.TakeRevealed && me.Fields[a.FieldNo].Count == 0
	}); ok {
		return a
	}

//line bot/bot.w:438

//line bot/bot.w:443
	if a, ok := pick(v.Legal, func(a bz.Action) bool {
		return a.Kind == bz.TossRevealed
	}); ok {
		return a
	}

//line bot/bot.w:439
	return v.Legal[0]
}

//line bot/bot.w:455
func duelDrawMove(v bz.View) bz.Action {
	me := v.Players[v.You]

//line bot/bot.w:189
	if a, ok := pick(v.Legal, func(a bz.Action) bool {
		return a.Kind == bz.Harvest && ripe(me.Fields[a.FieldNo])
	}); ok {
		return a
	}

//line bot/bot.w:458

//line bot/bot.w:252
	if a, ok := pick(v.Legal, func(a bz.Action) bool {
		if a.Kind != bz.TakeRevealed {
			return false
		}
		f := me.Fields[a.FieldNo]
		return f.Count > 0 && f.Crop == v.FaceUp[a.FaceUpNo]
	}); ok {
		return a
	}

//line bot/bot.w:459
	return endOr(v)
}

//line bot/bot.w:466
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

//line bot/bot.w:483
func endOr(v bz.View) bz.Action {
	if a, ok := pick(v.Legal, func(a bz.Action) bool {
		return a.Kind == bz.EndPhase
	}); ok {
		return a
	}
	return v.Legal[0]
}

//line bot/bot.w:495
func matchesField(me bz.PlayerView, b bz.Bean) bool {
	for _, f := range me.Fields {
		if f.Count > 0 && f.Crop == b {
			return true
		}
	}
	return false
}

//line bot/bot.w:507
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
//line bot/bot.w:527
//line bot/bot.w:528
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

//line bot/bot.w:556
	if !s.Over() {
		return nil, fmt.Errorf("판이 %d수에서 끝나지 않음(씨앗 %d, 단계 %v)",
			step, seed, s.Stage)
	}

//line bot/bot.w:548
	return s.Scores(), nil
}
