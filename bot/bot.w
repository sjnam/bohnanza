@i ../types.w

\input kotexgweb

\datethis
\def\title{보난자 봇}

@* 들어가며.
이 문서는 보난자 게임 엔진(\.{bohnanza})을 스스로 굴리는 {\it 봇\/}이다. 봇은
사람 대신 수를 고를 뿐, 그 지위는 앞서 지은 CLI\slash 웹 클라이언트와 조금도
다르지 않다: 엔진에서 한 플레이어의 |View|를 받아 읽고, 그 뷰에 담긴 합법수
가운데 하나를 골라 |Action|으로 돌려준다. 봇은 |State| 속을 들여다보지
않으므로, 남의 손패나 덱 속처럼 가려진 정보는 봇에게도 보이지 않는다---서버\slash
클라이언트 경계가 봇에서도 그대로 지켜진다. 규칙을 아는 것은 여전히 엔진뿐이다.

@ 보난자의 심장은 거래다. 그래서 이 봇은 {\bf 거래를 한다}: 남의 밭(공개
정보)을 보고 누가 어떤 콩을 원하는지 어림해, 내게 필요 없는 공개 카드를 그
콩을 기르는 상대에게 넘기고 내가 기르는 콩을 받아 온다. 다만 봇끼리 제안과
거절이 끝없이 오가는 것을 막으려 {\it 거래 예산\/}을 둔다---턴마다 유한한
제안 횟수를 정해 두고 다 쓰면 더는 제안하지 않으니, 게임은 반드시 끝난다.

@ 봇의 실력을 말이 아니라 숫자로 답하려고, 정책 세 가지를 둔다: 아무 합법수나
고르는 |Random|(실력의 밑바닥), 거래까지 하는 |Greedy|, 그리고 {\it 거래만
빼고\/} 똑같은 |Cautious|다. 마지막 둘을 맞대어 보면 ``거래가 실력을 얼마나
끌어올리는가''라는 물음에 곧장 답이 나온다.

@ 프로그램은 \GO/ 패키지 |bot|으로 나온다. 정책과 대전장은 주 출력 \.{bot.go}에,
실력을 재는 시험은 \.{bot\_test.go}에 함께 떨어진다. 아래 조각들이 위에서
아래로 쌓여 봇을 이룬다.
@c
package bot

import (
	"fmt"
	"math/rand/v2"

	bz "github.com/sjnam/bohnanza"
)

@<정책 인터페이스@>@;
@<무작위 정책@>@;
@<그리디 정책@>@;
@<밭 고르기와 거두기 도우미@>@;
@<심기 단계의 수@>@;
@<거래 단계의 수@>@;
@<거래 제안 만들기@>@;
@<제안에 응답하는 수@>@;
@<받은 콩 단계의 수@>@;
@<작은 도우미들@>@;
@<대전장@>@;

@* 정책.
정책은 뷰 하나를 받아 수 하나를 내는 함수다. 인터페이스로 두어, 대전장이
플레이어마다 다른 정책을 앉힐 수 있게 한다. 난수원을 함께 받는 것은 무작위
정책을 위한 것이다---그리디는 결정론적이라 이 인수를 쓰지 않는다.
@<정책 인터페이스@>=
type Policy interface {
	Act(v bz.View, rng *rand.Rand) bz.Action
}

@ 무작위 정책은 합법수 가운데 하나를 고르게 뽑는다. 실력의 밑바닥을 재는
잣대다. 자기 차례라면 합법수는 반드시 하나 이상이므로 빈 목록 걱정은 없다.
@<무작위 정책@>=
type Random struct{}

func (Random) Act(v bz.View, rng *rand.Rand) bz.Action {
	return v.Legal[rng.IntN(len(v.Legal))]
}

@ 그리디 정책은 상태를 조금 지닌다: 거래를 하는지 여부(|trade|)와, 이번 턴에
남은 거래 예산(|budget|)이다. 예산을 지녀야 봇끼리 제안이 맴도는 것을 막을 수
있다. |NewGreedy|는 거래하는 봇을, |NewCautious|는 거래만 빼고 똑같은 봇을
만든다---둘을 맞대어 거래의 값어치를 잰다.
@<그리디 정책@>=
type Greedy struct {
	trade  bool
	budget int
}

func NewGreedy() *Greedy   { return &Greedy{trade: true} }
func NewCautious() *Greedy { return &Greedy{trade: false} }

@ 단계에 따라 수를 고른다. 심기 단계는 곧 내 턴의 시작이므로, 여기서 거래
예산을 새로 채운다---인원의 두 배면 넉넉하다. 어느 갈래든 반드시 합법수
목록에서 골라 돌려주므로, 엔진이 이 수를 물리는 일은 없다.
@<그리디 정책@>=
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
	}
	return v.Legal[0]
}

@* 어림짐작의 밑감.
그리디의 판단은 몇 가지 작은 물음으로 쪼개진다. 이 밭이 다 익었는가? 이 콩은
어느 밭에 심어야 하는가? 자리를 비우려면 어느 밭을 거둘까? 먼저 그 물음들에
답하는 도우미를 짓는다.

@ 밭이 {\it 익었다\/}는 것은 콩미터의 맨 꼭대기 칸에 닿아, 더 심어도 코인이
늘지 않는 상태다. 그런 밭은 곧장 거두어 코인으로 바꾸고 자리를 비우는 것이
언제나 이득이다. 장수를 크게 더해 코인이 그대로면 꼭대기에 닿은 것이다.
@<밭 고르기와 거두기 도우미@>=
func ripe(f bz.FieldView) bool {
	if f.Count == 0 {
		return false
	}
	c := f.Crop.Coins(f.Count)
	return c >= 1 && c == f.Crop.Coins(f.Count+50)
}

@ 콩 |b|를 심을 가장 좋은 밭을 고른다. 같은 콩이 자라는 밭이 있으면 그
가운데 가장 많이 쌓인 밭을 골라 더미를 키우고, 없으면 빈 밭을 쓴다. 둘 다
없으면(모든 밭이 다른 콩으로 찼으면) 심을 자리가 없다는 뜻이다.
@<밭 고르기와 거두기 도우미@>=
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

@ 자리를 비워야 할 때 거둘 밭을 고른다. 합법한 거두기 수 가운데 코인을 가장
많이 주는 밭을 골라 은행에 넣는다(코인이 같으면 더 큰 더미를 턴다). 한 장짜리
밭 제한 때문에 애초에 거둘 수 없는 밭은 합법수 목록에 없으니, 여기서는 목록만
훑으면 된다.
@<밭 고르기와 거두기 도우미@>=
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

@* 심기 단계.
심기 단계에서 그리디의 방침은 이렇다. 익은 밭이 있으면 먼저 거두어 코인으로
바꾼다. 코인이 넉넉하고 밭이 두 칸뿐이면 세 번째 밭을 사 둔다---보난자에서
셋째 밭은 두고두고 값진 융통성이다. 그런 다음 맨 앞 카드를 가장 좋은 밭에
심는다.
@<심기 단계의 수@>=
func plantMove(v bz.View) bz.Action {
	me := v.Players[v.You]
	@<익은 밭이 있으면 거둔다@>@;
	@<코인이 남으면 세 번째 밭을 산다@>@;
	@<맨 앞 카드를 심거나, 자리를 비운다@>@;
	return endOr(v)
}

@ 익은 밭 거두기는 세 단계가 함께 쓰는 첫 번째 손질이다. 합법한 거두기 수
가운데 익은 밭을 가리키는 것이 있으면 그것을 돌려준다. 같은 조각을 심기\slash
거래\slash 받은 콩 단계가 모두 참조해 쓴다.
@<익은 밭이 있으면 거둔다@>=
if a, ok := pick(v.Legal, func(a bz.Action) bool {
	return a.Kind == bz.Harvest && ripe(me.Fields[a.FieldNo])
}); ok {
	return a
}

@ 코인이 셋 이상이고 아직 밭이 두 칸이면 세 번째 밭을 산다. 사고 나면 밭이
세 칸이 되어 이 수는 더 나오지 않으니, 게임당 많아야 한 번이다.
@<코인이 남으면 세 번째 밭을 산다@>=
if me.Coins >= 3 && len(me.Fields) == 2 {
	if a, ok := pick(v.Legal, func(a bz.Action) bool {
		return a.Kind == bz.BuyField
	}); ok {
		return a
	}
}

@ 맨 앞 카드를 심는다. 이미 한 장을 심어 단계를 끝낼 수 있는데, 남은 카드가
어느 밭과도 안 맞아 {\it 빈 밭에 새 작물\/}을 벌여야 한다면 심지 않고 단계를
끝낸다---둘째 카드로 굳이 세 번째 종류의 콩을 벌이는 것은 손해다. 반대로 아직
한 장도 못 심었으면 맨 앞 카드를 반드시 심어야 하니, 자리가 없으면 밭을 거두어
비운다.
@<맨 앞 카드를 심거나, 자리를 비운다@>=
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

@* 거래 단계.
활성 플레이어의 거래 단계다. 할 일은 공개 카드 두 장을 처리해 단계를 끝내는
것이다. 순서가 곧 우선순위다: 익은 밭을 거두고, 내 밭과 맞는 공개 카드를 집어
더미를 키우고, 남는 카드는 {\it 빈 밭이 있으면\/} 거기 놓는다. 여기까지는
비거래 봇과 같다. 거래는 {\bf 마지막 수단으로만} 쓴다---빈 밭이 없어 값진 밭을
헐어야 할 처지일 때, 그제야 필요 없는 카드를 남에게 넘긴다. 거래를 아껴야
공짜로 남을 살찌우는 자선을 면한다.
@<거래 단계의 수@>=
func (g *Greedy) tradeMove(v bz.View) bz.Action {
	me := v.Players[v.You]
	@<익은 밭이 있으면 거둔다@>@;
	@<내 밭과 맞는 공개 카드를 집는다@>@;
	@<공개 카드를 빈 밭에 놓는다@>@;
	@<예산이 남으면 필요 없는 카드를 넘긴다@>@;
	@<자리가 없으면 밭을 거두어 비운다@>@;
	return endOr(v)
}

@ 공개 카드 가운데 이미 자라는 밭과 같은 콩이 있으면 그리로 집어 더미를 키운다.
@<내 밭과 맞는 공개 카드를 집는다@>=
if a, ok := pick(v.Legal, func(a bz.Action) bool {
	if a.Kind != bz.TakeRevealed {
		return false
	}
	f := me.Fields[a.FieldNo]
	return f.Count > 0 && f.Crop == v.FaceUp[a.FaceUpNo]
}); ok {
	return a
}

@ 거래 봇이고 예산이 남았으면, 필요 없는 공개 카드를 남에게 넘기는 제안을
만들어 본다. 제안 하나마다 예산을 하나 깎는다. 제안이 서면 그것을 돌려주고,
설 자리가 없으면 다음 손질로 넘어간다.
@<예산이 남으면 필요 없는 카드를 넘긴다@>=
if g.trade && g.budget > 0 {
	if a, ok := proposeTrade(v); ok {
		g.budget--
		return a
	}
}

@ 맞는 밭이 없으면 빈 밭에 놓는다. 빈 밭에 놓을 수 있는 한 거래로 넘기지
않으므로, 이 손질을 제안보다 앞에 둔다.
@<공개 카드를 빈 밭에 놓는다@>=
if a, ok := pick(v.Legal, func(a bz.Action) bool {
	return a.Kind == bz.TakeRevealed && me.Fields[a.FieldNo].Count == 0
}); ok {
	return a
}

@ 여기까지 왔다면 빈 밭이 없어 공개 카드를 심을 자리가 없다. 그래도 공개
더미를 비워야 단계를 끝낼 수 있으니, 마지막으로 밭을 거두어 자리를 낸다---
값진 밭이라도 헐어야 한다. 바로 이 손해를 앞의 거래가 막으려 한 것이다.
@<자리가 없으면 밭을 거두어 비운다@>=
if len(v.FaceUp) > 0 {
	if a, ok := bestHarvest(v); ok {
		return a
	}
}

@* 거래 제안 만들기.
제안의 씨앗은 공개 정보다. 남의 밭은 모두에게 보이므로, 어떤 콩을 누가 기르는지
안다. 그래서 내게 필요 없는(내 밭과 안 맞는) 공개 카드 |b|마다, 그 콩을 기르는
상대를 찾아 넘긴다. 그냥 주기만 하면 자선이니, 내가 기르는 콩을 되받으려
한다---다만 그 콩이 상대에게 있는지는 가려져 있어 알 수 없으므로, 없으면 상대가
거절할 뿐이다(예산이 그 헛됨을 막는다).
@<거래 제안 만들기@>=
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
		@<상대 |o|에게 |b|를 넘기는 제안을 만든다@>@;
	}
	return bz.Action{}, false
}

@ 상대 |o|에게 |b|를 넘기되, 내가 기르는 콩 하나를 되받으려 한다. 되받을 콩이
있으면 교환을 내고, 없으면 그냥 넘기는 기부를 낸다---어차피 이 자리에 온 것은
밭을 헐어야 할 처지라, 카드를 넘겨 자리를 지키는 편이 낫기 때문이다.
@<상대 |o|에게 |b|를 넘기는 제안을 만든다@>=
if r, want := requestBean(me, v.Players[o]); want {
	return bz.Action{Kind: bz.ProposeTrade, Actor: v.You, To: o,
		GiveFaceUp: []bz.Bean{b}, GetHand: []bz.Bean{r}}, true
}
return bz.Action{Kind: bz.ProposeTrade, Actor: v.You, To: o,
	GiveFaceUp: []bz.Bean{b}}, true

@ 콩 |b|를 원하는 상대를 찾는다: 그 콩을 이미 기르는 플레이어면 원한다고 본다.
나 자신은 뺀다.
@<거래 제안 만들기@>=
func wanter(v bz.View, b bz.Bean) int {
	for i, p := range v.Players {
		if i != v.You && matchesField(p, b) {
			return i
		}
	}
	return -1
}

@ 상대에게서 되받을 콩을 고른다: 내가 기르는 콩 가운데, 상대는 안 기르고(그래야
상대도 선뜻 내줄 만하고), 아직 안 익은(더 필요한) 밭의 콩을 고르되, 가장 많이
쌓인 밭을 우선한다.
@<거래 제안 만들기@>=
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

@* 제안에 응답하기.
사람이나 다른 봇이 내민 제안은 받는다. 판단은 간단하다: 내가 받을 콩이 내
밭을 살찌우는 정도가, 내가 내줄 콩을 잃는 아픔보다 크면 수락한다. 요구받은
콩을 내가 실제로 쥐고 있지 않으면(수락해 봐야 엔진이 물릴 테니) 거절한다.
@<제안에 응답하는 수@>=
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

@ 이득을 셈한다. 받을 콩(제안자가 손패\slash 공개 카드에서 내주는 콩)은 내
|Acquired|로 들어와 곧 심어지고, 내줄 콩은 내 손패에서 빠진다. 받을 콩 가운데
내 밭과 맞는 수가, 내줄 콩 가운데 내 밭과 맞는 수보다 많으면 수락한다.
@<제안에 응답하는 수@>=
func worthAccepting(me bz.PlayerView, pr *bz.ProposalView) bool {
	give := pr.GetHand // 내가 손패에서 내주는 콩
	if !holds(me.Hand, give) {
		return false
	}
	gain := countMatching(me, pr.GiveHand) + countMatching(me, pr.GiveFaceUp)
	loss := countMatching(me, give)
	return gain > loss
}

@ 콩 목록 가운데 내 밭에서 이미 자라는 것의 수를 센다. 받을 콩이든 내줄
콩이든, ``내 밭과 맞는가''를 이 하나로 잰다.
@<제안에 응답하는 수@>=
func countMatching(me bz.PlayerView, bs []bz.Bean) int {
	n := 0
	for _, b := range bs {
		if matchesField(me, b) {
			n++
		}
	}
	return n
}

@* 받은 콩 단계.
거래로 받은 콩을 심는 단계다. 방침은 심기 단계와 같다: 익은 밭을 먼저 거두고,
받은 콩의 맨 앞 한 알을 가장 좋은 밭에 심되, 자리가 없으면 밭을 거두어 비운다.
받은 콩은 반드시 심어야 하므로 끝내는 수는 없다.
@<받은 콩 단계의 수@>=
func giftMove(v bz.View) bz.Action {
	me := v.Players[v.You]
	@<익은 밭이 있으면 거둔다@>@;
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

@* 작은 도우미들.
정책들이 함께 쓰는 잔손질을 모은다. |pick|은 합법수 목록에서 조건에 맞는 첫
수를 찾고, |hasKind|는 어떤 종류의 수가 목록에 있는지 본다.
@<작은 도우미들@>=
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

@ |endOr|은 단계를 끝내는 수가 있으면 그것을, 없으면 목록의 첫 수를 돌려주는
안전한 마무리다. 어림짐작이 아무 수도 고르지 못했을 때의 바닥이다.
@<작은 도우미들@>=
func endOr(v bz.View) bz.Action {
	if a, ok := pick(v.Legal, func(a bz.Action) bool {
		return a.Kind == bz.EndPhase
	}); ok {
		return a
	}
	return v.Legal[0]
}

@ |matchesField|는 콩 |b|가 내 밭에서 이미 자라는지 본다---상대가 어떤 콩을
원하는지, 내가 어떤 콩을 되받고 싶은지를 모두 이 하나로 잰다.
@<작은 도우미들@>=
func matchesField(me bz.PlayerView, b bz.Bean) bool {
	for _, f := range me.Fields {
		if f.Count > 0 && f.Crop == b {
			return true
		}
	}
	return false
}

@ |holds|는 콩 더미가 바라는 콩을 개수까지 담는지 본다---요구받은 콩을 내가
정말 쥐고 있는지 응답 때 확인하는 데 쓴다.
@<작은 도우미들@>=
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

@* 대전장.
이제 봇을 맞붙인다. |Play|는 정책 목록을 받아 그 인원으로 한 판을 끝까지 둔다.
매 수마다 지금 나설 사람의 뷰를 뽑아 그 자리의 정책에게 넘기고, 고른 수를
엔진에 적용한다---서버가 하는 일과 똑같되, 사람 대신 정책이 고를 뿐이다.
게임이 막히지 않도록 수에 상한을 둔다.
@<대전장@>=
func Play(ps []Policy, seed uint64) ([]int, error) {
	s, err := bz.New(len(ps), seed)
	if err != nil {
		return nil, err
	}
	rng := rand.New(rand.NewPCG(seed, 0x1234567))
	for step := 0; step < 100000 && !s.Over(); step++ {
		actor := s.ToAct()
		if actor < 0 {
			break
		}
		a := ps[actor].Act(s.View(actor), rng)
		if _, err := s.Apply(a); err != nil {
			return nil, fmt.Errorf("봇 %d의 수 적용 실패(씨앗 %d): %w", actor, seed, err)
		}
	}
	return s.Scores(), nil
}

@* 시험.
가장 궁금한 것을 시험이 답한다: 그리디가 랜덤을 이기는가, 그리고 {\bf 거래가
실력을 얼마나 끌어올리는가?} 시험은 재현 가능하도록 씨앗을 고정해 수백 판을
돌리고, 승률과 평균 점수를 |t.Logf|로 적어 둔다---%
{\tt go test -v}로 그 숫자를 볼 수 있다.
@(bot_test.go@>=
package bot

import "testing"

@<자리 승패 도우미@>@;
@<그리디 대 랜덤 시험@>@;
@<여러 명 대전 시험@>@;
@<거래가 점수를 올리는지 시험@>@;
@<거래 봇 대 비거래 봇 시험@>@;

@ 점수 목록에서 어느 자리가 홀로 최고점인지 본다. 공동 최고점은 무승부라
승리로 세지 않는다.
@<자리 승패 도우미@>=
func soleWinner(scores []int, seat int) bool {
	for i, sc := range scores {
		if i != seat && sc >= scores[seat] {
			return false
		}
	}
	return true
}

@ 2인전에서 그리디와 랜덤을 맞붙인다. 자리에 따른 선후 이점을 지우려고 씨앗마다
자리를 맞바꿔 두 판씩 둔다. 그리디의 승수가 랜덤의 승수를 넘어야 한다.
@<그리디 대 랜덤 시험@>=
func TestGreedyBeatsRandom(t *testing.T) {
	const N = 300
	gWins, rWins, ties := 0, 0, 0
	var gTot, rTot int
	for seed := uint64(0); seed < N; seed++ {
		for gSeat := 0; gSeat < 2; gSeat++ {
			ps := []Policy{Random{}, Random{}}
			ps[gSeat] = NewGreedy()
			scores, err := Play(ps, seed)
			if err != nil {
				t.Fatal(err)
			}
			g, r := scores[gSeat], scores[1-gSeat]
			gTot, rTot = gTot+g, rTot+r
			switch {
			case g > r:
				gWins++
			case g < r:
				rWins++
			default:
				ties++
			}
		}
	}
	games := 2 * N
	t.Logf("그리디 %d승 / 랜덤 %d승 / 무승부 %d (총 %d판)",
		gWins, rWins, ties, games)
	t.Logf("평균 점수 — 그리디 %.2f, 랜덤 %.2f",
		float64(gTot)/float64(games), float64(rTot)/float64(games))
	if gWins <= rWins {
		t.Errorf("그리디가 랜덤을 못 이김: %d대 %d", gWins, rWins)
	}
}

@ 3인전과 4인전에서도 그리디가 랜덤들 사이에서 공정한 몫---$1/n$---보다 훨씬
자주 이기는지 본다. 자리 이점을 지우려고 씨앗마다 그리디의 자리를 돌린다.
@<여러 명 대전 시험@>=
func TestArenaMultiplayer(t *testing.T) {
	const N = 300
	for _, n := range []int{3, 4} {
		wins := 0
		for seed := uint64(0); seed < N; seed++ {
			ps := make([]Policy, n)
			for i := range ps {
				ps[i] = Random{}
			}
			g := int(seed) % n
			ps[g] = NewGreedy()
			scores, err := Play(ps, seed)
			if err != nil {
				t.Fatal(err)
			}
			if soleWinner(scores, g) {
				wins++
			}
		}
		share := float64(wins) / float64(N)
		t.Logf("%d인전: 그리디 승률 %.1f%% (공정 몫 %.1f%%)",
			n, share*100, 100/float64(n))
		if share <= 1/float64(n) {
			t.Errorf("%d인전에서 그리디가 공정 몫도 못 넘김: %.3f", n, share)
		}
	}
}

@ 거래의 값어치를 잰다. 모두 비거래 봇인 판과 모두 거래 봇인 판의 평균
개인 점수를 견준다. 거래가 실력이라면 거래 봇들의 평균이 더 높아야 한다.
@<거래가 점수를 올리는지 시험@>=
func TestTradingRaisesScores(t *testing.T) {
	for _, n := range []int{2, 3, 4} {
		cautious := avgScore(t, n, false)
		trading := avgScore(t, n, true)
		t.Logf("%d인: 비거래 평균 %.2f → 거래 평균 %.2f",
			n, cautious, trading)
		if trading <= cautious {
			t.Errorf("%d인: 거래가 점수를 못 올림 (%.2f vs %.2f)",
				n, trading, cautious)
		}
	}
}

@ 한 정책으로 |n|명을 채워 |N|판을 두고, 평균 개인 점수를 낸다.
@<거래가 점수를 올리는지 시험@>=
func avgScore(t *testing.T, n int, trade bool) float64 {
	const N = 200
	total := 0
	for seed := uint64(0); seed < N; seed++ {
		ps := make([]Policy, n)
		for i := range ps {
			if trade {
				ps[i] = NewGreedy()
			} else {
				ps[i] = NewCautious()
			}
		}
		scores, err := Play(ps, seed)
		if err != nil {
			t.Fatal(err)
		}
		for _, sc := range scores {
			total += sc
		}
	}
	return float64(total) / float64(N*n)
}

@ 마지막으로 거래 봇과 비거래 봇을 직접 맞붙여, 거래가 {\it 이기는\/} 실력인지
본다(점수만 오르고 승부는 손해일 수도 있으니). 자리를 맞바꿔 두 판씩 두고
승수를 견준다.
@<거래 봇 대 비거래 봇 시험@>=
func TestTradingVsCautious(t *testing.T) {
	const N = 300
	tWins, cWins, ties := 0, 0, 0
	for seed := uint64(0); seed < N; seed++ {
		for tSeat := 0; tSeat < 2; tSeat++ {
			ps := make([]Policy, 2)
			ps[tSeat] = NewGreedy()
			ps[1-tSeat] = NewCautious()
			scores, err := Play(ps, seed)
			if err != nil {
				t.Fatal(err)
			}
			switch t2, c := scores[tSeat], scores[1-tSeat]; {
			case t2 > c:
				tWins++
			case t2 < c:
				cWins++
			default:
				ties++
			}
		}
	}
	t.Logf("거래 봇 %d승 / 비거래 봇 %d승 / 무승부 %d (총 %d판)",
		tWins, cWins, ties, 2*N)
}

@* 색인.
