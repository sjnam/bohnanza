//line ai/ai.w:848
package ai

import "testing"

//line ai/ai.w:862
func soleWinner(scores []int, seat int) bool {
	for i, sc := range scores {
		if i != seat && sc >= scores[seat] {
			return false
		}
	}
	return true
}

//line ai/ai.w:874
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

//line ai/ai.w:913
func TestArenaMultiplayer(t *testing.T) {
	const N = 300
	for _, n := range []int{3, 4, 5, 6, 7} {
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

//line ai/ai.w:946
func TestTradingRaisesScores(t *testing.T) {
	for _, n := range []int{3, 4} {
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

//line ai/ai.w:962
func TestDuelHasNoTrading(t *testing.T) {
	if a, b := avgScore(t, 2, false), avgScore(t, 2, true); a != b {
		t.Errorf("2인 결투에 거래가 스몄다: 비거래 %.4f, 거래 %.4f", a, b)
	}
}

//line ai/ai.w:970
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

//line ai/ai.w:997
func TestTradingVsCautious(t *testing.T) {
	const N = 400
	wins, mine, theirs := 0, 0, 0
	for seed := uint64(0); seed < N; seed++ {
		ps := make([]Policy, 4)
		for i := range ps {
			ps[i] = NewCautious()
		}
		seat := int(seed) % 4
		ps[seat] = NewGreedy()
		scores, err := Play(ps, seed)
		if err != nil {
			t.Fatal(err)
		}

//line ai/ai.w:1017
		if soleWinner(scores, seat) {
			wins++
		}
		for i, sc := range scores {
			if i == seat {
				mine += sc
			} else {
				theirs += sc
			}
		}

//line ai/ai.w:1012
	}

//line ai/ai.w:1035
	mineAvg, theirsAvg := float64(mine)/N, float64(theirs)/(3*N)
	t.Logf("거래 봇 평균 %.2f, 비거래 봇 평균 %.2f, 거래 봇 승률 %.1f%%(공정 몫 25%%)",
		mineAvg, theirsAvg, 100*float64(wins)/N)
	if mineAvg <= theirsAvg {
		t.Errorf("거래 봇이 비거래 봇보다 점수가 낮음: %.2f 대 %.2f", mineAvg, theirsAvg)
	}

//line ai/ai.w:1014
}

//line ai/ai.w:1060
func TestStrategistBeatsGreedy(t *testing.T) {
	const N = 600
	for _, n := range []int{3, 4} {
		base, bs, _ := oddOneOut(t, n, N, func() Policy { return NewGreedy() })
		got, gs, os := oddOneOut(t, n, N, func() Policy { return NewStrategist() })
		t.Logf("%d인: v2 기준선 %.1f%%(점수 %.2f) → v3 %.1f%%(점수 %.2f 대 %.2f), %+.1fpp",
			n, base*100, bs, got*100, gs, os, (got-base)*100)
		if got <= base {
			t.Errorf("%d인: v3이 v2 기준선을 못 넘김 (%.3f 대 %.3f)", n, got, base)
		}
	}
}

//line ai/ai.w:1076
func oddOneOut(t *testing.T, n, N int, mk func() Policy) (float64, float64, float64) {
	wins, mine, theirs := 0, 0, 0
	for seed := uint64(0); seed < uint64(N); seed++ {
		ps := make([]Policy, n)
		for i := range ps {
			ps[i] = NewGreedy()
		}
		seat := int(seed) % n
		ps[seat] = mk()
		scores, err := Play(ps, seed)
		if err != nil {
			t.Fatal(err)
		}

//line ai/ai.w:1096
		if soleWinner(scores, seat) {
			wins++
		}
		for i, sc := range scores {
			if i == seat {
				mine += sc
			} else {
				theirs += sc
			}
		}

//line ai/ai.w:1090
	}
	return float64(wins) / float64(N), float64(mine) / float64(N),
		float64(theirs) / float64(N*(n-1))
}

//line ai/ai.w:1112
func TestStrategistWidensTheGap(t *testing.T) {
	const N = 400
	_, gs, go_ := oddOneOut(t, 3, N, func() Policy { return NewGreedy() })
	_, ss, os := oddOneOut(t, 3, N, func() Policy { return NewStrategist() })
	t.Logf("3인: v2 자리 %.2f(상대 %.2f, 차 %+.2f), v3 자리 %.2f(상대 %.2f, 차 %+.2f)",
		gs, go_, gs-go_, ss, os, ss-os)
	if ss-os <= gs-go_ {
		t.Errorf("v3이 v2보다 차이를 못 벌림: %+.2f 대 %+.2f", ss-os, gs-go_)
	}
}

//line ai/ai.w:1130
func TestAllStrategistShrinksThePie(t *testing.T) {
	const N = 300
	v2 := allSame(t, 3, N, func() Policy { return NewGreedy() })
	v3 := allSame(t, 3, N, func() Policy { return NewStrategist() })
	none := allSame(t, 3, N, func() Policy { return NewCautious() })
	t.Logf("3인 평균 개인 점수 — 모두 v2 %.2f, 모두 v3 %.2f, 모두 비거래 %.2f",
		v2, v3, none)
	if !(none <= v3 && v3 < v2) {
		t.Errorf("파이 크기가 예상 밖: 비거래 %.2f, v3 %.2f, v2 %.2f", none, v3, v2)
	}
}

//line ai/ai.w:1143
func allSame(t *testing.T, n, N int, mk func() Policy) float64 {
	total := 0
	for seed := uint64(0); seed < uint64(N); seed++ {
		ps := make([]Policy, n)
		for i := range ps {
			ps[i] = mk()
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
