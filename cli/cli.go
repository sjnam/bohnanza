//line cli/cli.w:26
package main

import (
	"bufio"
	"fmt"
	"math/rand/v2"
	"os"
	"strconv"
	"strings"

	bz "github.com/sjnam/bohnanza"
	"github.com/sjnam/bohnanza/bot"
)

var in = bufio.NewReader(os.Stdin)

//line cli/cli.w:147
func fieldStr(f bz.FieldView) string {
	if f.Count == 0 {
		return "[ · ]"
	}
	return fmt.Sprintf("[%s×%d]", f.Crop.Name(), f.Count)
}

//line cli/cli.w:156
func cardNames(cs []bz.Bean) string {
	if len(cs) == 0 {
		return "없음"
	}
	names := make([]string, len(cs))
	for i, c := range cs {
		names[i] = c.Name()
	}
	return strings.Join(names, ",")
}

//line cli/cli.w:171
func drawBoard(v bz.View) {
	fmt.Printf("\n───────── %s 단계 · %d번 플레이어 차례 ─────────\n",
		v.PhaseName, v.ToAct)
	for _, p := range v.Players {
		mark := " "
		if p.Index == v.You {
			mark = "▶"
		}
		fmt.Printf("%s %d번 (코인 %d, 손패 %d장): ", mark, p.Index, p.Coins, p.HandCount)
		for _, f := range p.Fields {
			fmt.Print(fieldStr(f), " ")
		}
		fmt.Println()
	}

//line cli/cli.w:193
	if v.Pending != nil {
		pr := v.Pending
		give := append(append([]bz.Bean{}, pr.GiveHand...), pr.GiveFaceUp...)
		fmt.Printf("  ★ %d번의 제안: [%s] 받고 손패에서 [%s] 내주기 → 수락/거절\n",
			pr.From, cardNames(give), cardNames(pr.GetHand))
	}

//line cli/cli.w:186

//line cli/cli.w:204
	if len(v.FaceUp) > 0 {
		fmt.Print("  공개 카드: ")
		for i, c := range v.FaceUp {
			fmt.Printf("[%d:%s] ", i, c.Name())
		}
		fmt.Println()
	}
	me := v.Players[v.You]
	if len(me.Hand) > 0 {
		fmt.Print("  손패(0번이 맨 앞): ")
		names := make([]string, len(me.Hand))
		for i, c := range me.Hand {
			names[i] = fmt.Sprintf("%d:%s", i, c.Name())
		}
		fmt.Println(strings.Join(names, " "))
	}
	if len(me.Acquired) > 0 {
		fmt.Print("  받은 콩: ")
		for _, c := range me.Acquired {
			fmt.Print(c.Name(), " ")
		}
		fmt.Println()
	}

//line cli/cli.w:187
}

//line cli/cli.w:233
func chooseAction(v bz.View) (bz.Action, bool) {
	acts := v.Legal
	fmt.Println("  둘 수 있는 수:")
	for i, a := range acts {
		fmt.Printf("    %d) %s\n", i, a)
	}
	for {
		fmt.Print("  번호 선택> ")
		line, err := in.ReadString('\n')
		if err != nil {
			return bz.Action{}, false
		}
		line = strings.TrimSpace(line)
		if line == "" || line == "q" {
			return bz.Action{}, false
		}
		n, err := strconv.Atoi(line)
		if err != nil || n < 0 || n >= len(acts) {
			fmt.Println("  0부터", len(acts)-1, "사이의 번호를 넣으세요.")
			continue
		}
		return acts[n], true
	}
}

//line cli/cli.w:49
func main() {
	players, humans, seed := 3, 1, uint64(1)

//line cli/cli.w:66
	if len(os.Args) > 1 {
		players, _ = strconv.Atoi(os.Args[1])
	}
	if len(os.Args) > 2 {
		humans, _ = strconv.Atoi(os.Args[2])
	}
	if len(os.Args) > 3 {
		if v, err := strconv.ParseUint(os.Args[3], 10, 64); err == nil {
			seed = v
		}
	}

//line cli/cli.w:52
	s, err := bz.New(players, seed)
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

//line cli/cli.w:83
	bots := make([]bot.Policy, players)
	for i := humans; i < players; i++ {
		bots[i] = bot.NewStrategist()
	}
	rng := rand.New(rand.NewPCG(seed, seed^0x9e3779b97f4a7c15))

//line cli/cli.w:58
	fmt.Printf("보난자 시작! %d명(사람 %d, 봇 %d), 씨앗 %d\n",
		players, humans, players-humans, seed)

//line cli/cli.w:94
	for !s.Over() {
		actor := s.ToAct()
		if actor < 0 {
			break
		}
		view := s.View(actor)

//line cli/cli.w:107
		var act bz.Action
		if p := bots[actor]; p != nil {
			act = p.Act(view, rng)
			fmt.Printf("[봇 %d] %s\n", actor, act)
		} else {
			drawBoard(view)
			a, ok := chooseAction(view)
			if !ok {
				fmt.Println("게임을 중단합니다.")
				return
			}
			act = a
		}
		events, err := s.Apply(act)
		if err != nil {
			fmt.Println("오류:", err)
			continue
		}
		for _, e := range events {
			fmt.Println("  →", e)
		}

//line cli/cli.w:101
	}

//line cli/cli.w:61

//line cli/cli.w:131
	fmt.Println("\n===== 게임 종료 =====")
	scores := s.Scores()
	best, winner := -1, 0
	for i, sc := range scores {
		fmt.Printf("%d번 플레이어: %d코인\n", i, sc)
		if sc > best {
			best, winner = sc, i
		}
	}
	fmt.Printf("승자: %d번 플레이어 (%d코인)\n", winner, best)

//line cli/cli.w:62
}
