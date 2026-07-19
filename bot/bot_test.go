//line bot.w:522
package bot

import "testing"

//line bot.w:535
func soleWinner(scores []int, seat int) bool {
	for i, sc := range scores {
		if i != seat && sc >= scores[seat] {
			return false
		}
	}
	return true
}

//line bot.w:547
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

//line bot.w:584
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

//line bot.w:615
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

//line bot.w:630
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

//line bot.w:657
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
