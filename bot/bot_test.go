//line bot/bot.w:567
package bot

import "testing"

//line bot/bot.w:580
func soleWinner(scores []int, seat int) bool {
	for i, sc := range scores {
		if i != seat && sc >= scores[seat] {
			return false
		}
	}
	return true
}

//line bot/bot.w:592
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

//line bot/bot.w:629
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

//line bot/bot.w:662
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

//line bot/bot.w:678
func TestDuelHasNoTrading(t *testing.T) {
	if a, b := avgScore(t, 2, false), avgScore(t, 2, true); a != b {
		t.Errorf("2인 결투에 거래가 스몄다: 비거래 %.4f, 거래 %.4f", a, b)
	}
}

//line bot/bot.w:686
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

//line bot/bot.w:713
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

//line bot/bot.w:733
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

//line bot/bot.w:728
	}

//line bot/bot.w:751
	mineAvg, theirsAvg := float64(mine)/N, float64(theirs)/(3*N)
	t.Logf("거래 봇 평균 %.2f, 비거래 봇 평균 %.2f, 거래 봇 승률 %.1f%%(공정 몫 25%%)",
		mineAvg, theirsAvg, 100*float64(wins)/N)
	if mineAvg <= theirsAvg {
		t.Errorf("거래 봇이 비거래 봇보다 점수가 낮음: %.2f 대 %.2f", mineAvg, theirsAvg)
	}

//line bot/bot.w:730
}
