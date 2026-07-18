@i ../types.w

\input kotexgweb

\datethis
\def\title{보난자 CLI}

@* 들어가며.
이 작은 프로그램은 보난자 게임 엔진(\.{bohnanza})을 터미널에서 굴려 보는
검증용 클라이언트다. 웹 프런트를 붙이기 전에, $2\sim4$명이 한자리에 둘러앉아
같은 화면을 돌려 쓰는 핫시트(hot-seat) 방식으로 규칙과 턴 진행이 제대로
도는지 눈으로 확인하는 것이 목적이다.

책임은 철저히 나눈다. 규칙은 엔진이 안다. 이 CLI는 앞으로 붙일 웹 클라이언트와
{\it 똑같은 계약\/}만 쓴다: 엔진에서 한 플레이어의 |View|를 받아 그리고,
그 뷰에 담긴 합법수를 번호로 늘어놓고, 고른 |Action|을 엔진에 돌려보낸다.
엔진의 속 상태(|State|)를 직접 들여다보지 않으므로, 남의 손패나 덱 속처럼
가려진 정보는 여기서도 볼 수 없다---서버\slash 클라이언트 경계가 CLI에서도
그대로 지켜진다.

@ 실행법은 |bohnanza-cli [인원수] [사람수] [씨앗]|이다. 인원수를 안 주면 3명,
사람수를 안 주면 1명이다---그러니 아무 인수 없이 부르면 당신 하나가 봇 둘과
겨룬다. 사람은 0번부터 낮은 자리를, 봇은 남은 높은 자리를 맡는다. 씨앗을 안
주면 1로 시작하므로, 같은 인수는 늘 같은 게임이 된다---버그를 재현하기 좋다.
@c
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

@<판을 그리는 함수들@>@;
@<한 수를 받는 함수@>@;
@<메인 루프@>@;

@ |main|은 인수를 읽어 게임을 차리고, 끝날 때까지 한 수씩 돌린 뒤 점수를
알린다. 뼈대가 곧 게임의 흐름이다.
@<메인 루프@>=
func main() {
	players, humans, seed := 3, 1, uint64(1)
	@<인수를 읽는다@>@;
	s, err := bz.New(players, seed)
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
	@<봇을 앉힌다@>@;
	fmt.Printf("보난자 시작! %d명(사람 %d, 봇 %d), 씨앗 %d\n",
		players, humans, players-humans, seed)
	@<끝날 때까지 한 수씩 둔다@>@;
	@<최종 점수를 알린다@>@;
}

@ 인수는 차례로 인원수, 사람수, 씨앗이다. 없으면 각각 3, 1, 1이다.
@<인수를 읽는다@>=
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

@ 사람이 맡지 않은 높은 자리에 그리디 봇을 앉힌다. |bots[p]|가 |nil|이면
$p$번은 사람 자리다. 봇은 결정론적이라 난수원을 쓰지 않지만, 정책 계약이
난수원을 받으므로 하나 마련해 둔다.
@<봇을 앉힌다@>=
bots := make([]bot.Policy, players)
for i := humans; i < players; i++ {
	bots[i] = bot.NewGreedy()
}
rng := rand.New(rand.NewPCG(seed, seed^0x9e3779b97f4a7c15))

@ 매 수마다 지금 나설 사람의 뷰를 받아 판을 그리고, 뷰에 담긴 합법수 중 하나를
고르게 해 엔진에 적용한다. 서버라면 |s.View(actor)|를 JSON으로 실어 보내고
클라이언트가 고른 |Action|을 받아 |s.Apply|할 자리다. 여기서는 그 왕복을
한 프로세스 안에서 흉내 낼 뿐이다.
@<끝날 때까지 한 수씩 둔다@>=
for !s.Over() {
	actor := s.ToAct()
	if actor < 0 {
		break
	}
	view := s.View(actor)
	@<봇이면 봇이, 사람이면 사람이 한 수 둔다@>@;
}

@ 지금 나설 자리가 봇이면 정책에게 물어 곧장 두고, 무슨 수를 뒀는지 한 줄로
알린다. 사람 자리면 예전처럼 판을 그려 주고 번호로 고르게 한다. 어느 쪽이든
고른 수를 엔진에 적용하고 이벤트를 흘려 준다.
@<봇이면 봇이, 사람이면 사람이 한 수 둔다@>=
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

@ 게임이 끝나면 각자 점수를 세어 가장 높은 사람을 가린다.
@<최종 점수를 알린다@>=
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

@* 판 그리기.
판을 그리는 일은 순수 출력이다. 넘겨받은 |View|만 읽어 사람이 보기 좋게
늘어놓을 뿐, 아무것도 바꾸지 않는다. 밭 한 칸은 ``콩이름×장수''로, 빈 밭은
점으로 그린다. 콩미터 이름은 엔진의 |Bean.Name|을 그대로 쓴다.
@<판을 그리는 함수들@>=
func fieldStr(f bz.FieldView) string {
	if f.Count == 0 {
		return "[ · ]"
	}
	return fmt.Sprintf("[%s×%d]", f.Crop.Name(), f.Count)
}

@ 콩 목록을 이름으로 잇는다. 대기 중인 제안을 보여 줄 때 쓴다.
@<판을 그리는 함수들@>=
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

@ |drawBoard|는 뷰 하나로 전체 판을 그린다: 위쪽에 모든 플레이어의 밭\slash
코인\slash 손패 장수를(공개 정보), 가운데에 공개 카드를, 아래에 뷰 주인의
손패를 늘어놓는다. 뷰 주인은 |▶|로 표시한다.
@<판을 그리는 함수들@>=
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
	@<대기 중인 제안을 그린다@>@;
	@<공개 카드와 내 손패를 그린다@>@;
}

@ 응답을 기다리는 거래가 있으면, 지금 나설 상대에게 무엇을 주고받는 교환인지
보여 준다. 제안자가 내주는 콩은 곧 이 사람의 ``받은 콩''이 되고, 요구하는
콩은 이 사람의 손패에서 빠진다.
@<대기 중인 제안을 그린다@>=
if v.Pending != nil {
	pr := v.Pending
	give := append(append([]bz.Bean{}, pr.GiveHand...), pr.GiveFaceUp...)
	fmt.Printf("  ★ %d번의 제안: [%s] 받고 손패에서 [%s] 내주기 → 수락/거절\n",
		pr.From, cardNames(give), cardNames(pr.GetHand))
}

@ 공개 카드가 있으면 번호와 함께 보이고, 뷰 주인의 손패도 번호를 매겨 보인다.
손패의 0번이 곧 다음에 심을 ``맨 앞'' 카드다. 남의 손패는 뷰에 카드가 없으므로
장수만 위에 나온다.
@<공개 카드와 내 손패를 그린다@>=
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

@* 수 고르기.
|chooseAction|은 뷰에 담긴 합법수를 번호로 늘어놓고, 사람이 고른 번호를
돌려준다. 규칙은 엔진이 이미 걸러 주었으므로, 여기서는 목록에 없는 번호만
막으면 된다. 빈 줄이나 |q|는 중단 신호로 본다.
@<한 수를 받는 함수@>=
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

@* 색인.
