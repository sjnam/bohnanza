@i types.w

\input kotexgweb

\datethis
\def\title{보난자 게임 엔진}

@* 들어가며.
이 문서는 보드게임 {\it 보난자\/}(Bohnanza)의 순수 게임 엔진이다. 목표는
화면도 네트워크도 모르는, 오직 규칙만 아는 엔진을 짜는 것이다. 엔진은 오직
세 가지 일을 한다: 게임을 새로 만들고(|New|), 지금 둘 수 있는 수를
알려주고(|Legal|), 수 하나를 받아 상태를 옮긴다(|Apply|). 화면 출력과 입력은
따로 떨어진 CLI(\.{cli/cli.w})가 맡는다. 이렇게 나눠 두면 나중에 웹 프런트를
붙일 때 엔진을 한 줄도 고치지 않아도 된다.

보난자는 콩 농사 게임이다. 154장의 콩 카드를 심고 길러 코인으로 바꾼다.
게임의 정체성은 두 규칙에서 나온다. 첫째, {\bf 손패는 순서를 바꿀 수 없다}---
카드는 늘 손패 맨 앞에서부터 꺼내 심는다. 둘째, {\bf 한 밭에는 한 종류의 콩만}
심을 수 있다. 이 두 제약이 ``원치 않는 콩을 남에게 넘기는'' 거래를 게임의
심장으로 만든다.

@ 한 턴은 네 단계로 흐른다. 이 엔진은 그 흐름을 상태 기계로 옮긴다.
$$\vbox{\halign{\indent\bf#\hfil&\quad#\hfil\cr
심기&    손패 맨 앞 카드를 심는다(1장 필수, 2장까지 선택)\cr
거래&    덱에서 2장을 뒤집어 공개하고, 활성 플레이어가 나눠 준다\cr
받은콩&  거래로 받은 콩을 각자 즉시 심는다\cr
보충&    덱에서 3장 뽑아 손패 뒤에 붙이고 다음 사람에게 넘긴다\cr}}$$
게임은 덱이 바닥나는 순간 끝난다. 그때 각자 남은 밭을 모두
거두어 코인을 세고, 코인이 가장 많은 사람이 이긴다. 거래는 활성 플레이어가
상대에게 교환을 내밀면 상대가 수락하거나 거절하는 양방향 방식이고, 콩미터
수치와 카드 장수는 규칙서(영어\slash Rio Grande 판, 열한 종 154장)를 그대로
따른다. 한 장짜리 밭 수확 제한도 규칙대로 건다.

@ 인원에 따라 규칙이 갈린다. 4인은 위의 기본 규칙 그대로지만, $2\sim3$인은
규칙서가 따로 정한 {\it 공식 변형\/}을 쓴다. 3인은 카카오콩을 빼고 밭 3칸으로
시작하며 보충을 전원이 한 장씩 돌고, 2인은 아예 {\it 콩 결투\/}라는 다른 턴
구조로 논다---거래가 없고, 대신 뽑은 콩 가운데 원치 않는 것을 상대에게 넘긴다.
이 갈래를 |Variant| 하나에 값으로 모아 두었으므로, 규칙의 ``인원에 따라 무엇이
다른가''는 한 곳에서만 읽으면 된다.

@ 프로그램은 \GO/ 패키지 |bohnanza|로 나온다. \.{gtangle}을 실행하면 주 출력
\.{bohnanza.go}와 시험 파일 \.{bohnanza\_test.go}가 함께 떨어진다. 아래
조각들이 위에서 아래로 쌓여 엔진을 이룬다.
@c
package bohnanza

import (
	"encoding/json"
	"fmt"
	"math/rand/v2"
	"strings"
)

@<콩과 콩미터@>@;
@<변형 규칙@>@;
@<게임 상태@>@;
@<덱 다루기@>@;
@<밭에 심고 거두기@>@;
@<턴 넘기기@>@;
@<액션@>@;
@<합법수 열거@>@;
@<이벤트@>@;
@<액션 적용@>@;
@<점수와 불변식@>@;
@<플레이어 뷰@>@;

@* 콩과 콩미터.
콩은 열한 종류다. 각 콩은 덱에 들어가는 장수가 다르고---흔한 콩일수록
많다---{\it 콩미터\/}라는 환전표를 하나씩 가진다. 콩미터는 ``코인 $k$개를
받으려면 같은 콩을 몇 장 거두어야 하는가''를 적은 네 칸짜리 표다. 예컨대
커피콩은 4장에 1코인, 7장에 2코인, 10장에 3코인, 12장에 4코인이다. 0은 그
코인 수에 도달할 수 없음을 뜻한다(정원콩과 카카오콩은 1코인 칸이 비어 있다).

@ 콩을 정수 |Bean|으로 표현하고, 종류별 이름\slash 장수\slash 콩미터를 한
테이블에 담는다. 카드 한 장은 곧 콩 한 알이므로 |Card|를 |Bean|의 별명으로
둔다. 콩미터 수치와 장수는 규칙서(영어\slash Rio Grande 판)와 대조해 확정한
값이다---구조가 데이터에 의존하지 않으므로, 다른 판본을 따르려면 이 표만
고치면 된다.

한 가지 판본 차이를 밝혀 둔다. 왁스콩의 콩미터는 구판이 $4,7,9,11$이고 2016년
개정판이 $4,8,11,13$인데, 여기서는 개정판을 따랐다. 인원별 변형 규칙을 개정판
규칙서에서 가져왔으니 콩미터도 같은 판본으로 맞추는 편이 앞뒤가 맞기 때문이다.
나머지 열 종류는 두 판본이 같다.
@s Bean int
@<콩과 콩미터@>=
type Bean int

const (
	Coffee Bean = iota
	Wax
	Blue
	Chili
	Stink
	Green
	Soy
	BlackEyed
	Red
	Garden
	Cocoa
	NumBeans
)

type Card = Bean // |Card|는 콩 한 알과 같다.

@ 각 콩의 고정 정보를 담는 표다. |Meter|의 네 칸은 차례로 1,2,3,4코인에
필요한 장수다.
@<콩과 콩미터@>=
type BeanInfo struct {
	Name  string
	Count int    // 덱에 들어가는 장수
	Meter [4]int // 1,2,3,4 코인에 필요한 장수 (0은 도달 불가)
}

var beanTable = [NumBeans]BeanInfo{
	Coffee:    {"커피콩", 24, [4]int{4, 7, 10, 12}},
	Wax:       {"왁스콩", 22, [4]int{4, 8, 11, 13}},
	Blue:      {"파랑콩", 20, [4]int{4, 6, 8, 10}},
	Chili:     {"고추콩", 18, [4]int{3, 6, 8, 9}},
	Stink:     {"악취콩", 16, [4]int{3, 5, 7, 8}},
	Green:     {"완두콩", 14, [4]int{3, 5, 6, 7}},
	Soy:       {"메주콩", 12, [4]int{2, 4, 6, 7}},
	BlackEyed: {"동부콩", 10, [4]int{2, 4, 5, 6}},
	Red:       {"강낭콩", 8, [4]int{2, 3, 4, 5}},
	Garden:    {"정원콩", 6, [4]int{0, 2, 3, 0}},
	Cocoa:     {"카카오콩", 4, [4]int{0, 2, 3, 4}},
}

const TotalCards = 154 // 덱 전체 장수(154)다.

@ 두 조회 함수다. |Name|은 콩 이름을, |Coins|는 콩 $n$장을 거두었을 때 받는
코인 수를 콩미터로 계산한다. 콩미터의 각 칸을 앞에서부터 훑어, 장수가 충분한
가장 높은 코인 칸을 답으로 삼는다.
@<콩과 콩미터@>=
func (b Bean) Name() string { return beanTable[b].Name }

func (b Bean) Coins(n int) int {
	c := 0
	for i, need := range beanTable[b].Meter {
		if need != 0 && n >= need {
			c = i + 1
		}
	}
	return c
}

@* 변형 규칙.
인원에 따라 달라지는 것들을 |Variant| 한 값에 모은다. 규칙이 코드 곳곳에
흩어져 |if| 문으로 갈라지면 어느 판본을 노는 중인지 알 수 없게 되므로,
차이를 데이터로 뽑아 두고 코드는 그 값을 읽기만 하게 했다.

@ 여섯 가지가 갈린다. 덱에서 빼는 콩, 시작 밭 칸수, 세 번째 밭을 살 수
있는지, 덱이 몇 번째로 바닥날 때 끝나는지, 보충 단계에서 몇 장을 뽑는지,
그리고 그 보충을 활성 플레이어 혼자 하는지 전원이 한 장씩 도는지다. 마지막
|Duel|은 2인 전용 턴 구조를 켜는 스위치다.
@s Variant int
@<변형 규칙@>=
type Variant struct {
	Drop       []Bean // 이 인원에서는 덱에 넣지 않는 콩
	StartField int    // 각자 시작할 때 받는 밭 칸수
	ExtraField bool   // 세 번째 밭을 살 수 있는가
	LastPass   int    // 덱이 이만큼 바닥나면 게임이 끝난다
	Refill     int    // 보충 단계에서 뽑는 장수
	RoundRobin bool   // 보충을 전원이 한 장씩 도는가
	Duel       bool   // 2인 콩 결투 규칙인가
}

@ 인원별 표다. 4인은 기본 규칙이고, 3인과 2인은 규칙서의 공식 변형이다.
2인 결투는 3인 변형을 물려받은 뒤 정원콩까지 더 빼고, 덱이 {\it 처음\/}
바닥날 때 끝나며, 보충이 두 장이다.
@<변형 규칙@>=
func variantFor(n int) Variant {
	switch n {
	case 2:
		return Variant{Drop: []Bean{Garden, Cocoa}, StartField: 3,
			LastPass: 1, Refill: 2, Duel: true}
	case 3:
		return Variant{Drop: []Bean{Cocoa}, StartField: 3,
			LastPass: 2, Refill: 1, RoundRobin: true}
	}
	return Variant{StartField: 2, ExtraField: true, LastPass: 3, Refill: 3}
}

func (v Variant) drops(b Bean) bool {
	for _, d := range v.Drop {
		if d == b {
			return true
		}
	}
	return false
}

@ 표의 근거를 밝혀 둔다. 개정판 규칙서는 카카오\slash 왁스\slash 커피를 더한
열한 종 덱을 ``세 가지 새 콩'' 변형으로 두고, 그 변형에서 3인은 카카오콩을 빼고
밭 3칸으로 시작하며 보충을 전원이 시계방향으로 한 장씩 하고, 덱이 두 번째로
바닥날 때 끝난다고 적는다. 2인 콩 결투는 이 3인 변형을 그대로 물려받되 정원콩과
카카오콩을 빼고, 자기 턴에만 밭을 팔 수 있으며, 덱이 처음 바닥날 때 끝난다.

여기서 한 가지는 일부러 규칙서와 다르게 두었다. 개정판은 저 보충 규칙을 3인만이
아니라 변형 전체($3\sim7$인)에 걸겠다고 적지만, 이 엔진의 4인은 예전부터 활성
플레이어가 세 장을 뽑는 기본 규칙으로 돌아왔고 봇의 승률 기준도 거기 맞춰 두었다.
$2\sim3$인 변형을 {\it 더하는\/} 것이 목적이므로 4인은 건드리지 않았다. 4인까지
개정판에 맞추고 싶다면 |variantFor|의 마지막 줄만 고치면 된다.

@* 게임 상태.
게임의 모든 것은 |State| 하나에 담긴다. 플레이어들, 덱과 버림 더미, 거래에서
뒤집은 공개 카드, 게임에서 빠진 카드(밭 값과 변형에서 뺀 콩), 그리고 지금이
누구 차례의 어느 단계인지다. 난수는 |State| 안에 씨앗으로 심어 두어, 같은 씨앗과 같은
수순은 언제나 같은 게임이 되게 한다---재현 가능한 시험의 뿌리다.

@ 플레이어는 손패, 밭, 거래로 받아 아직 못 심은 콩(|Acquired|), 그리고
거두어 모은 코인 더미(|Treasury|)를 가진다. 코인을 정수가 아니라 카드 더미로
쥐는 것은 일부러 그런 것이다. 그래야 게임 어디에도 카드가 새거나 겹치지 않는
{\it 카드 보존\/} 불변식을 그대로 검사할 수 있다.
@s Player int
@s Field int
@<게임 상태@>=
type Field struct {
	Crop  Bean // 이 밭에서 자라는 콩(작물)
	Count int
}

func (f Field) Empty() bool { return f.Count == 0 }

type Player struct {
	Hand     []Card  // 순서 고정: 맨 앞에서만 꺼낸다
	Fields   []Field // 처음 2칸, 3번째 밭을 사면 3칸
	Acquired []Card  // 거래로 받아 아직 못 심은 콩
	Treasury []Card  // 거두어 모은 코인
}

func (p *Player) Coins() int { return len(p.Treasury) }

@ 턴의 단계는 |Phase|로 나타낸다. 심기\slash 거래\slash 받은 콩 심기 세
단계가 사람의 선택을 받고, 보충은 자동이라 단계로 두지 않는다. 2인 결투는
거래가 없는 대신 |PhaseOffer|(상대가 남긴 콩을 심거나 버리기)와
|PhaseDuelDraw|(뽑은 콩을 심고 나머지를 상대에게 남기기) 두 단계를 더 쓴다.
게임이 끝나면 |GameOver|로 굳는다.
@s Phase int
@<게임 상태@>=
type Phase int

const (
	PhasePlant Phase = iota // 손패에서 심기
	PhaseTrade              // 공개 카드 나누기
	PhaseHarvestGifts       // 받은 콩 심기
	PhaseOffer              // 결투: 상대가 남긴 콩 처리
	PhaseDuelDraw           // 결투: 뽑은 콩을 심고 남기기
	GameOver
)

@ 단계 이름을 한글로 옮긴다. 뷰와 CLI가 함께 쓴다.
@<게임 상태@>=
func (p Phase) String() string {
	switch p {
	case PhasePlant:
		return "심기"
	case PhaseTrade:
		return "거래"
	case PhaseHarvestGifts:
		return "받은 콩 심기"
	case PhaseOffer:
		return "받은 제안"
	case PhaseDuelDraw:
		return "뽑아 나누기"
	}
	return "종료"
}

@ 이제 |State| 본체다. |Active|는 현재 턴의 플레이어, |PlantCount|는 이번
심기 단계에서 심은 장수(0,1,2), |Exhaust|는 덱이 바닥난 횟수다. |Rules|는
이 판이 따르는 인원별 변형이고, |HandTossed|는 결투에서 이번 턴에 손패를 한 장
버렸는지를 적는다(턴마다 한 장까지다). |rng|는 직렬화하지 않는 내부
난수원이라 소문자로 감춘다.
@s State int
@<게임 상태@>=
type State struct {
	Players    []*Player
	Deck       []Card
	Discard    []Card
	FaceUp     []Card // 뒤집은 공개 카드(결투에서는 상대에게 넘길 제안)
	Removed    []Card // 게임에서 빠진 카드(밭 값과 변형에서 뺀 콩)
	Active     int
	Stage      Phase // 지금 이 턴이 어느 단계인지
	PlantCount int
	Exhaust    int
	HandTossed bool      // 결투: 이번 턴에 손패를 버렸는가
	Rules      Variant   // 이 판이 따르는 인원별 변형
	Pending    *Proposal // 응답을 기다리는 거래 제안(없으면 |nil|)

	rng *rand.Rand
}

@ 거래 제안 |Proposal|은 활성 플레이어가 상대에게 내미는 교환이다. 세 더미로
나뉜다: 내가 손패에서 내주는 콩, 내가 공개 카드에서 내주는 콩, 그리고 상대가
손패에서 내주는 콩이다. 상대의 콩이 없으면 그저 기부다. 카드는 값(콩 종류)으로
적는다---같은 콩은 서로 구별할 필요가 없기 때문이다.
@<게임 상태@>=
type Proposal struct {
	From       int
	To         int
	GiveHand   []Card // From이 손패에서 내주는 콩
	GiveFaceUp []Card // From이 공개 카드에서 내주는 콩
	GetHand    []Card // To가 손패에서 내주는 콩
}

@ |New|는 인원수와 씨앗을 받아 새 게임을 차린다. 먼저 인원에 맞는 변형을
고르고, 콩미터 테이블대로 덱을 쌓아 섞고, 각 플레이어에게 변형이 정한 만큼의
밭을 주고 손패를 돌아가며 다섯 장씩 나눈다. 인원은 이 간단판에서 $2\sim4$명만
받는다.
@<게임 상태@>=
const StartingHand = 5

func New(numPlayers int, seed uint64) (*State, error) {
	if numPlayers < 2 || numPlayers > 4 {
		return nil, fmt.Errorf("보난자: 인원은 2~4명이어야 한다 (%d명 요청)", numPlayers)
	}
	s := &State{rng: rand.New(rand.NewPCG(seed, seed^0x9e3779b97f4a7c15)),
		Rules: variantFor(numPlayers)}
	@<덱을 쌓고 섞는다@>@;
	@<플레이어를 앉히고 손패를 돌린다@>@;
	return s, nil
}

@ 콩미터 테이블을 그대로 펼쳐 덱을 만든 뒤 한 번 섞는다. 변형이 빼라고 한
콩은 덱 대신 |Removed|로 보낸다---{\it 상자에 도로 넣는\/} 카드도 어딘가에는
있어야 카드 보존 불변식이 154장 그대로 성립하기 때문이다.
@<덱을 쌓고 섞는다@>=
for b := Bean(0); b < NumBeans; b++ {
	pile := &s.Deck
	if s.Rules.drops(b) {
		pile = &s.Removed
	}
	for i := 0; i < beanTable[b].Count; i++ {
		*pile = append(*pile, b)
	}
}
s.rng.Shuffle(len(s.Deck), func(i, j int) {
	s.Deck[i], s.Deck[j] = s.Deck[j], s.Deck[i]
})

@ 손패는 카드 게임의 관례대로 한 장씩 돌아가며 나눈다.
@<플레이어를 앉히고 손패를 돌린다@>=
for i := 0; i < numPlayers; i++ {
	s.Players = append(s.Players, &Player{Fields: make([]Field, s.Rules.StartField)})
}
for k := 0; k < StartingHand; k++ {
	for i := 0; i < numPlayers; i++ {
		c, _ := s.draw()
		s.Players[i].Hand = append(s.Players[i].Hand, c)
	}
}

@* 덱 다루기.
덱에서 카드를 뽑는 |draw|는 게임의 시계다. 덱이 비면 버림 더미를 섞어 새
덱으로 삼되, 이렇게 바닥나는 것을 |Exhaust|로 센다. 변형이 정한 |LastPass|
번째로 바닥나는 순간이 게임의 끝이므로(4인은 세 번째, 3인은 두 번째, 2인
결투는 첫 번째다), 그때는 카드를 내주지 않고 실패를 알린다.
@<덱 다루기@>=
func (s *State) draw() (Card, bool) {
	if len(s.Deck) == 0 {
		s.Exhaust++
		if s.Exhaust >= s.Rules.LastPass || len(s.Discard) == 0 {
			return 0, false
		}
		s.Deck, s.Discard = s.Discard, nil
		s.rng.Shuffle(len(s.Deck), func(i, j int) {
			s.Deck[i], s.Deck[j] = s.Deck[j], s.Deck[i]
		})
	}
	c := s.Deck[len(s.Deck)-1]
	s.Deck = s.Deck[:len(s.Deck)-1]
	return c, true
}

@ 뽑기가 실패하면(덱이 세 번째로 바닥나면) 게임을 |GameOver|로 굳힌다.
여러 곳에서 이 처리를 되풀이하므로 작은 도우미로 묶는다.
@<덱 다루기@>=
func (s *State) endIfEmpty(ok bool) bool {
	if !ok {
		s.Stage = GameOver
	}
	return ok
}

@* 밭에 심고 거두기.
심기와 거두기는 상태를 바꾸는 두 저수준 연산이다. |plant|는 콩 한 알을 밭에
놓는다: 빈 밭이면 그 콩으로 채우고, 같은 콩이 있는 밭이면 한 장 보태고, 다른
콩이 있는 밭이면 규칙 위반이라 거절한다.
@<밭에 심고 거두기@>=
func (s *State) plant(p *Player, field int, b Bean) error {
	if field < 0 || field >= len(p.Fields) {
		return fmt.Errorf("보난자: 밭 번호 %d가 범위를 벗어남", field)
	}
	f := &p.Fields[field]
	switch {
	case f.Empty():
		f.Crop, f.Count = b, 1
	case f.Crop == b:
		f.Count++
	default:
		return fmt.Errorf("보난자: %s 밭에 %s를 심을 수 없음", f.Crop.Name(), b.Name())
	}
	return nil
}

@ 거두기에는 보난자의 한 가지 제한이 붙는다: {\bf 다른 밭에 두 장 이상 있으면,
한 장짜리 밭은 거둘 수 없다}. 코인 한 푼 못 받는 밭을 헐어 자리를 억지로 비우는
꾀를 막는 규칙이다. |canHarvest|가 이 판정을 한 곳에 모은다---빈 밭은 못 거두고,
한 장짜리 밭은 다른 밭이 모두 한 장 이하일 때만 거둘 수 있다.
@<밭에 심고 거두기@>=
func (p *Player) canHarvest(field int) bool {
	f := p.Fields[field]
	if f.Count == 0 {
		return false
	}
	if f.Count == 1 {
		for j := range p.Fields {
			if j != field && p.Fields[j].Count > 1 {
				return false
			}
		}
	}
	return true
}

@ 이 제한 덕분에 막다른 골목은 생기지 않는다. 콩이 있는 밭 가운데 가장 많은
밭은 언제나 거둘 수 있기 때문이다---그 밭의 장수가 2 이상이면 한 장짜리가
아니라 걸리지 않고, 장수가 1이면 모든 밭이 한 장 이하라 역시 걸리지 않는다.
그러니 심어야 하는데 자리가 없어도, 거둘 밭은 반드시 하나는 남는다.

@ |harvest|는 밭을 통째로 거둔다. 먼저 위 제한을 확인한 뒤, 콩미터로 코인 수를
정해 그만큼은 |Treasury|로 옮겨 코인이 되고, 나머지 콩은 버림 더미로 간다.
밭은 다시 빈칸이 된다.
@<밭에 심고 거두기@>=
func (s *State) harvest(p *Player, field int) (int, error) {
	if field < 0 || field >= len(p.Fields) {
		return 0, fmt.Errorf("보난자: 밭 번호 %d가 범위를 벗어남", field)
	}
	if !p.canHarvest(field) {
		return 0, fmt.Errorf("보난자: 다른 밭에 두 장 이상 있으면 한 장짜리 밭은 못 거둠")
	}
	f := &p.Fields[field]
	coins := f.Crop.Coins(f.Count)
	for i := 0; i < coins; i++ {
		p.Treasury = append(p.Treasury, f.Crop)
	}
	for i := 0; i < f.Count-coins; i++ {
		s.Discard = append(s.Discard, f.Crop)
	}
	*f = Field{}
	return coins, nil
}

@* 턴 넘기기.
한 턴의 마지막(보충 단계)은 자동이다. 덱에서 카드를 뽑아 손패 {\it 뒤\/}에
순서대로 붙이고, 차례를 다음 사람에게 넘기고, 단계를 그 턴의 첫 단계로
되돌린다. 뽑다가 덱이 바닥나면 그 자리에서 게임이 끝난다.
@<턴 넘기기@>=
func (s *State) endTurn() {
	if !s.refill() {
		return
	}
	s.Active = (s.Active + 1) % len(s.Players)
	s.PlantCount = 0
	s.HandTossed = false
	s.Stage = s.openingPhase()
}

@ 보충은 변형에 따라 두 모양이다. 기본(4인)과 결투(2인)는 활성 플레이어
혼자 |Refill|장을 뽑고, 3인 변형은 전원이 활성 플레이어부터 시계방향으로
한 장씩 뽑는다. 두 모양을 한 겹의 이중 반복으로 적었다---바깥은 몇 바퀴,
안쪽은 누가 뽑는가이고, 시계방향이 아니면 첫 사람에서 곧장 빠져나온다.
@<턴 넘기기@>=
func (s *State) refill() bool {
	n := len(s.Players)
	for k := 0; k < s.Rules.Refill; k++ {
		for i := 0; i < n; i++ {
			c, ok := s.draw()
			if !s.endIfEmpty(ok) {
				return false
			}
			p := s.Players[(s.Active+i)%n]
			p.Hand = append(p.Hand, c)
			if !s.Rules.RoundRobin {
				break
			}
		}
	}
	return true
}

@ 새 턴이 어느 단계에서 열리는지다. 보통은 심기지만, 결투에서 앞사람이
남긴 콩이 상 위에 있으면 그것을 처리하는 |PhaseOffer|부터 연다. 첫 턴에는
남긴 콩이 없으므로 시작 플레이어는 자연히 이 단계를 건너뛴다---규칙서가
말하는 ``시작 플레이어는 첫 턴에 1단계를 생략한다''가 저절로 이루어진다.
@<턴 넘기기@>=
func (s *State) openingPhase() Phase {
	if s.Rules.Duel && len(s.FaceUp) > 0 {
		return PhaseOffer
	}
	return PhasePlant
}

@ 어느 플레이어가 지금 수를 두어야 하는지는 단계가 정한다. 심기와 거래,
그리고 결투의 두 단계는 활성 플레이어의 몫이고, 받은 콩 심기 단계에서는 아직
못 심은 콩을 쥔 플레이어가 낮은 번호부터 차례로 나선다. 아무도 없거나 게임이
끝났으면 $-1$을 돌려준다.
@<턴 넘기기@>=
func (s *State) ToAct() int {
	switch s.Stage {
	case PhasePlant, PhaseOffer, PhaseDuelDraw:
		return s.Active
	case PhaseTrade:
		if s.Pending != nil {
			return s.Pending.To // 제안을 기다리는 동안은 상대 차례
		}
		return s.Active
	case PhaseHarvestGifts:
		for i := range s.Players {
			if len(s.Players[i].Acquired) > 0 {
				return i
			}
		}
	}
	return -1
}

@ 받은 콩 단계가 끝났는지, 즉 아무도 못 심은 콩을 들고 있지 않은지 본다.
@<턴 넘기기@>=
func (s *State) giftsPending() bool {
	for i := range s.Players {
		if len(s.Players[i].Acquired) > 0 {
			return true
		}
	}
	return false
}

@* 액션.
플레이어가 엔진에 건네는 수 하나가 |Action|이다. 종류를 |Kind|로 두고, 필요한
값---밭 번호, 카드 위치, 행위자, 기부 받을 사람---을 함께 담는다. 인터페이스
대신 납작한 구조체로 둔 것은 합법수를 목록으로 열거하고 CLI에서 메뉴로
찍기에 이 편이 편해서다.
@s ActionKind int
@s Action int
@<액션@>=
type ActionKind int

const (
	PlantFront   ActionKind = iota // 손패 맨 앞을 밭에 심기
	Harvest                        // 밭 거두기
	BuyField                       // 코인 3으로 세 번째 밭 사기
	EndPhase                       // 현재 단계 끝내기
	TakeRevealed                   // 공개 카드를 내 밭에 심기
	ProposeTrade                   // 거래(교환 또는 기부)를 제안
	RespondTrade                   // 제안을 수락 또는 거절
	PlantGift                      // 받은 콩을 밭에 심기
	TossRevealed                   // 결투: 공개 카드를 버림 더미로
	TossHand                       // 결투: 손패 아무 데서나 한 장 버리기
)

@ 새 갈래는 반드시 목록 {\it 끝\/}에 붙였다. 웹 클라이언트가 |ActionKind|를
JSON 숫자로 받아 갈래를 가르므로, 중간에 끼워 넣으면 이미 나가 있는 화면의
버튼이 통째로 어긋나기 때문이다. 액션 본체에는 |HandNo| 한 칸을 더한다---
|TossHand|가 손패 몇 번째를 버리는지 가리키는 자리다.
@<액션@>=
type Action struct {
	Kind     ActionKind `json:"kind"`
	Actor    int        `json:"player"` // 이 수를 두는 사람
	FieldNo  int        `json:"field"`  // 심거나 거둘 밭 번호
	FaceUpNo int        `json:"card"`   // |TakeRevealed|에서 공개 카드 번호
	HandNo   int        `json:"hand"`   // |TossHand|에서 버릴 손패 번호
	To       int        `json:"to"`     // 거래 상대

	// |ProposeTrade|용: 주고받을 콩을 값으로 적는다.
	GiveHand   []Card `json:"giveHand,omitempty"`
	GiveFaceUp []Card `json:"giveFaceUp,omitempty"`
	GetHand    []Card `json:"getHand,omitempty"`

	Accept bool `json:"accept,omitempty"` // |RespondTrade|용: 수락 여부
}

@ 사람이 읽을 이름표를 붙여 두면 CLI가 메뉴를 그리기 좋다.
@<액션@>=
func (a Action) String() string {
	switch a.Kind {
	case PlantFront:
		return fmt.Sprintf("맨 앞 카드를 %d번 밭에 심기", a.FieldNo)
	case Harvest:
		return fmt.Sprintf("%d번 밭 거두기", a.FieldNo)
	case BuyField:
		return "세 번째 밭 사기(코인 3)"
	case EndPhase:
		return "이 단계 끝내기"
	case TakeRevealed:
		return fmt.Sprintf("공개 카드 %d번을 %d번 밭에 심기", a.FaceUpNo, a.FieldNo)
	case ProposeTrade:
		return a.tradeString()
	case RespondTrade:
		if a.Accept {
			return "제안 수락"
		}
		return "제안 거절"
	case PlantGift:
		return fmt.Sprintf("받은 콩을 %d번 밭에 심기", a.FieldNo)
	case TossRevealed:
		return fmt.Sprintf("공개 카드 %d번 버리기", a.FaceUpNo)
	case TossHand:
		return fmt.Sprintf("손패 %d번 버리기", a.HandNo)
	}
	return "알 수 없는 수"
}

@ 거래 제안은 주는 콩과 받을 콩을 이름으로 늘어놓아 문장으로 만든다. 콩 목록을
쉼표로 잇는 |beanNames|는 이벤트 메시지에서도 쓴다.
@<액션@>=
func beanNames(cs []Card) string {
	if len(cs) == 0 {
		return "없음"
	}
	names := make([]string, len(cs))
	for i, c := range cs {
		names[i] = c.Name()
	}
	return strings.Join(names, ",")
}

func (a Action) tradeString() string {
	give := append(append([]Card{}, a.GiveHand...), a.GiveFaceUp...)
	return fmt.Sprintf("%d번에게 [%s] 주고 [%s] 받기 제안",
		a.To, beanNames(give), beanNames(a.GetHand))
}

@* 합법수 열거.
|Legal|은 주어진 플레이어가 지금 둘 수 있는 모든 수를 모아 준다. CLI 메뉴,
웹 버튼, 무작위 시험이 모두 이 하나를 공유하므로, 규칙의 ``무엇이 가능한가''는
여기 한 곳에만 적힌다. 자기 차례가 아니거나 게임이 끝났으면 빈 목록이다.
@<합법수 열거@>=
func (s *State) Legal(player int) []Action {
	if s.Stage == GameOver || player != s.ToAct() {
		return nil
	}
	switch s.Stage {
	case PhasePlant:
		return s.legalPlant(player)
	case PhaseTrade:
		if s.Pending != nil {
			return s.legalRespond(player)
		}
		return s.legalTrade(player)
	case PhaseHarvestGifts:
		return s.legalGifts(player)
	case PhaseOffer:
		return s.legalOffer(player)
	case PhaseDuelDraw:
		return s.legalDuelDraw(player)
	}
	return nil
}

@ 심기 단계. 아직 두 장을 다 심지 않았고 손패가 남아 있으면, 맨 앞 카드를
심을 수 있는 밭마다 수를 하나씩 낸다. 언제든 밭을 거둘 수 있고, 변형이
허락하고 밭이 두 칸뿐인데 코인이 3 이상이면 세 번째 밭을 살 수 있다($2\sim3$인
변형은 밭 3칸으로 시작하는 대신 더 사지 못한다). 한 장 이상 심었거나 손패가
비면 단계를 끝낼 수 있고, 그때 결투라면 손패를 한 장 버리는 수도 함께 낸다.
@<합법수 열거@>=
func (s *State) legalPlant(player int) []Action {
	p := s.Players[player]
	var acts []Action
	if s.PlantCount < 2 && len(p.Hand) > 0 {
		front := p.Hand[0]
		for f := range p.Fields {
			if p.Fields[f].Empty() || p.Fields[f].Crop == front {
				acts = append(acts, Action{Kind: PlantFront, Actor: player, FieldNo: f})
			}
		}
	}
	acts = append(acts, s.harvestActions(player)...)
	if s.Rules.ExtraField && len(p.Fields) == 2 && p.Coins() >= 3 {
		acts = append(acts, Action{Kind: BuyField, Actor: player})
	}
	if s.PlantCount >= 1 || len(p.Hand) == 0 {
		acts = append(acts, s.tossActions(player)...)
		acts = append(acts, Action{Kind: EndPhase, Actor: player})
	}
	return acts
}

@ 결투의 2단계에서는 심기를 마친 뒤 손패 {\it 아무 자리에서나\/} 한 장을
버림 더미에 앞면으로 놓을 수 있다---턴마다 한 장까지다. 손패는 순서가 곧
규칙이라 같은 콩이라도 어느 자리를 빼느냐에 따라 남는 순서가 달라지므로,
종류별로 묶지 않고 자리마다 하나씩 낸다.
@<합법수 열거@>=
func (s *State) tossActions(player int) []Action {
	if !s.Rules.Duel || s.HandTossed {
		return nil
	}
	var acts []Action
	for i := range s.Players[player].Hand {
		acts = append(acts, Action{Kind: TossHand, Actor: player, HandNo: i})
	}
	return acts
}

@ 밭 거두기 수는 여러 단계에서 쓰이므로 따로 뽑아 둔다: 규칙상 거둘 수 있는
밭마다 거두는 수를 하나씩 낸다(한 장짜리 밭 제한을 여기서 반영한다).
@<합법수 열거@>=
func (s *State) harvestActions(player int) []Action {
	p := s.Players[player]
	var acts []Action
	for f := range p.Fields {
		if p.canHarvest(f) {
			acts = append(acts, Action{Kind: Harvest, Actor: player, FieldNo: f})
		}
	}
	return acts
}

@ 거래 단계(제안 대기 중이 아닐 때). 활성 플레이어는 공개 카드를 자기 밭에
심거나, 밭을 거두어 자리를 비우거나, 상대와 거래를 제안할 수 있다. 공개 카드를
모두 치웠으면 단계를 끝낸다.
@<합법수 열거@>=
func (s *State) legalTrade(player int) []Action {
	var acts []Action
	for c := range s.FaceUp {
		acts = append(acts, s.takeActions(player, c)...)
	}
	acts = append(acts, s.harvestActions(player)...)
	acts = append(acts, s.proposeActions(player)...)
	if len(s.FaceUp) == 0 {
		acts = append(acts, Action{Kind: EndPhase, Actor: player})
	}
	return acts
}

@ 제안을 기다리는 상대가 낼 수 있는 수는 수락과 거절이다. 다만 {\it 수락\/}은
요구받은 콩을 상대가 실제로 쥐고 있을 때만 낸다---없는 콩을 요구하는 제안은
수락해도 엔진이 물리므로, 애초에 합법수로 내지 않아야 목록이 정직하다(웹은
누를 수 없는 수락 버튼을 그리지 않아도 된다). 상대는 자기 손패를 보므로 이
판정에 남의 정보가 새지 않는다. 거절은 언제나 낼 수 있다.
@<합법수 열거@>=
func (s *State) legalRespond(player int) []Action {
	var acts []Action
	if s.Pending != nil && containsAll(s.Players[player].Hand, s.Pending.GetHand) {
		acts = append(acts, Action{Kind: RespondTrade, Actor: player, Accept: true})
	}
	return append(acts, Action{Kind: RespondTrade, Actor: player, Accept: false})
}

@ 공개 카드 하나를 심을 수 있는 밭마다 |TakeRevealed| 수를 낸다.
@<합법수 열거@>=
func (s *State) takeActions(player, card int) []Action {
	p := s.Players[player]
	b := s.FaceUp[card]
	var acts []Action
	for f := range p.Fields {
		if p.Fields[f].Empty() || p.Fields[f].Crop == b {
			acts = append(acts, Action{Kind: TakeRevealed, Actor: player, FaceUpNo: card, FieldNo: f})
		}
	}
	return acts
}

@ 제안 열거는 대표적인 거래만 편다: 내 카드(손패 또는 공개) 한 장을 상대 손패
한 장과 맞바꾸는 1대1 교환과, 아무것도 받지 않고 주는 기부다. 같은 콩은
서로 같으므로 종류별로 하나씩만 낸다. |Apply|는 여러 장짜리 임의 거래도
받으므로, 웹 UI는 이 목록에 매이지 않고 더 자유로운 제안을 보낼 수 있다.
@<합법수 열거@>=
func (s *State) proposeActions(player int) []Action {
	var acts []Action
	mine := distinct(s.Players[player].Hand)
	faceup := distinct(s.FaceUp)
	for to := range s.Players {
		if to == player {
			continue
		}
		theirs := distinct(s.Players[to].Hand)
		@<상대 |to|와의 제안을 편다@>@;
	}
	return acts
}

@ 내가 내줄 콩(손패에서 또는 공개 카드에서) 하나마다, 상대 손패 콩 하나와
맞바꾸는 교환과 그냥 주는 기부를 낸다.
@<상대 |to|와의 제안을 편다@>=
for _, gb := range mine {
	for _, tb := range theirs {
		acts = append(acts, Action{Kind: ProposeTrade, Actor: player, To: to,
			GiveHand: []Card{gb}, GetHand: []Card{tb}})
	}
	acts = append(acts, Action{Kind: ProposeTrade, Actor: player, To: to,
		GiveHand: []Card{gb}})
}
for _, gb := range faceup {
	for _, tb := range theirs {
		acts = append(acts, Action{Kind: ProposeTrade, Actor: player, To: to,
			GiveFaceUp: []Card{gb}, GetHand: []Card{tb}})
	}
	acts = append(acts, Action{Kind: ProposeTrade, Actor: player, To: to,
		GiveFaceUp: []Card{gb}})
}

@ 카드 슬라이스에서 중복을 없앤 콩 목록을 만든다---제안을 종류별로 하나씩만
내기 위함이다.
@<합법수 열거@>=
func distinct(cs []Card) []Card {
	seen := make(map[Card]bool)
	var out []Card
	for _, c := range cs {
		if !seen[c] {
			seen[c] = true
			out = append(out, c)
		}
	}
	return out
}

@ 받은 콩 심기 단계. 지금 나설 플레이어는 못 심은 콩의 맨 앞 한 알을 심을 수
있는 밭마다 수를 내고, 자리가 없으면 밭을 거두어 비운다.
@<합법수 열거@>=
func (s *State) legalGifts(player int) []Action {
	p := s.Players[player]
	var acts []Action
	b := p.Acquired[0]
	for f := range p.Fields {
		if p.Fields[f].Empty() || p.Fields[f].Crop == b {
			acts = append(acts, Action{Kind: PlantGift, Actor: player, FieldNo: f})
		}
	}
	acts = append(acts, s.harvestActions(player)...)
	return acts
}

@ 결투 1단계. 상대가 남긴 콩이 상 위에 있다. 한 알씩, 심을 수 있는 밭에
심거나 그냥 버린다---어느 쪽이든 상에서 사라지므로 여기서 막히는 일은
없다. 자리가 없으면 밭을 거두어 비울 수도 있다. 남김없이 처리해야 다음
단계로 넘어가므로 단계를 끝내는 수는 따로 두지 않는다.
@<합법수 열거@>=
func (s *State) legalOffer(player int) []Action {
	var acts []Action
	for c := range s.FaceUp {
		acts = append(acts, s.takeActions(player, c)...)
		acts = append(acts, Action{Kind: TossRevealed, Actor: player, FaceUpNo: c})
	}
	return append(acts, s.harvestActions(player)...)
}

@ 결투 3단계. 뽑아 놓은 콩 가운데 원하는 것만 심고, 밭을 거두어 팔 수도
있다. 단계를 끝내면 {\it 남은 콩이 그대로 상대의 제안이 된다\/}---그래서
1단계와 달리 아무 때나 끝낼 수 있고, 하나도 심지 않고 통째로 넘겨도 된다.
@<합법수 열거@>=
func (s *State) legalDuelDraw(player int) []Action {
	var acts []Action
	for c := range s.FaceUp {
		acts = append(acts, s.takeActions(player, c)...)
	}
	acts = append(acts, s.harvestActions(player)...)
	return append(acts, Action{Kind: EndPhase, Actor: player})
}

@* 이벤트.
|Apply|는 무슨 일이 있었는지 이벤트로 알린다. 이벤트는 한때 완성된 한국어
문장이었다. 편하기는 했으나, 규칙만 알아야 할 엔진이 화면에 쓸 말까지 짓는
셈이라 이 프로그램이 내세운 경계를 스스로 허무는 자리였다. 게다가 문장에 박힌
것은 되돌릴 수 없다: 엔진은 참가자 이름을 모르니 ``0번 플레이어''라고 적을
수밖에 없고, 이름을 아는 클라이언트도 문자열을 헤집지 않고는 고칠 도리가 없다.

그래서 이벤트는 이제 {\it 무슨 일이 있었는지를 값으로\/} 나른다. 문장 만들기는
그릴 줄 아는 쪽---이름도 알고 글꼴도 고를 수 있는 클라이언트---의 몫이다.
@s EventKind int
@s Event int
@<이벤트@>=
type EventKind string

@ 열두 가지 일이 일어난다. 문자열을 값으로 삼아, \.{JSON}으로 나가도 숫자가
아니라 제 이름이 보이게 했다---|curl|로 스트림을 들여다볼 때나 클라이언트에서
갈래를 나눌 때나, 뜻이 그대로 드러나는 편이 낫다.
@<이벤트@>=
const (
	Planted       EventKind = "planted"       // 손패 맨 앞 카드를 밭에 심음
	PlantedFaceUp EventKind = "plantedFaceUp" // 공개 카드를 밭에 심음
	PlantedGift   EventKind = "plantedGift"   // 거래로 받은 콩을 밭에 심음
	Harvested     EventKind = "harvested"     // 밭을 거두어 코인을 얻음
	BoughtField   EventKind = "boughtField"   // 세 번째 밭을 삼
	Revealed      EventKind = "revealed"      // 덱에서 공개 카드가 뒤집힘
	DeckEmptied   EventKind = "deckEmptied"   // 덱이 바닥나 게임이 끝남
	GiftStage     EventKind = "giftStage"     // 받은 콩을 심는 단계로 넘어감
	TurnPassed    EventKind = "turnPassed"    // 턴을 넘김
	TradeProposed EventKind = "tradeProposed" // 거래를 제안
	TradeRejected EventKind = "tradeRejected" // 제안을 거절
	TradeAccepted EventKind = "tradeAccepted" // 교환 성사
	Tossed        EventKind = "tossed"        // 콩을 버림 더미에 버림
	Offered       EventKind = "offered"       // 남은 콩을 상대에게 넘김
	Fished        EventKind = "fished"        // 버림 더미에서 같은 콩을 끌어올림
)

@ 한 이벤트가 나르는 값이다. 갈래마다 쓰는 칸이 다르다---심기는 |Crop|과
|FieldNo|를, 거두기는 |Coins|를, 거래는 |To|와 두 콩 목록을 쓴다. 읽는 쪽은
|Kind|를 보고 제게 필요한 칸만 집으면 된다. 사람이 일으키지 않은 일(공개 카드가
뒤집히는 것 따위)은 |Actor|가 |NoActor|다.
@<이벤트@>=
const NoActor = -1

type Event struct {
	Kind    EventKind `json:"kind"`
	Actor   int       `json:"actor"`          // 이 일을 한 사람
	To      int       `json:"to"`             // 거래 상대
	Crop    Bean      `json:"bean"`           // 이 일에 걸린 콩
	FieldNo int       `json:"field"`          // 심거나 거둔 밭 번호
	Coins   int       `json:"coins"`          // 거두어 얻은 코인
	Give    []Card    `json:"give,omitempty"` // 제안자가 내주는 콩
	Get     []Card    `json:"get,omitempty"`  // 제안자가 받는 콩
}

@ 그래도 터미널처럼 단출한 곳을 위해 기본 문장 하나는 마련해 둔다. 이것은
{\it 편의\/}일 뿐 유일한 표현이 아니다---웹은 이 메서드를 쓰지 않고 이름과
꾸밈을 얹어 제 손으로 그린다. 엔진이 이름을 모르므로 여기서는 자리 번호로
적는다.
@<이벤트@>=
func (e Event) String() string {
	switch e.Kind {
	@<갈래마다 기본 문장을 짓는다@>@;
	}
	return string(e.Kind)
}

@ @<갈래마다 기본 문장을 짓는다@>=
case Planted, PlantedFaceUp, PlantedGift:
	return fmt.Sprintf("%d번이 %s%s %d번 밭에 심음", e.Actor,
		e.Crop.Name(), objectParticle(e.Crop.Name()), e.FieldNo)
case Harvested:
	return fmt.Sprintf("%d번이 %s 밭을 거둬 코인 %d개 얻음",
		e.Actor, e.Crop.Name(), e.Coins)
case BoughtField:
	return fmt.Sprintf("%d번이 세 번째 밭을 삼", e.Actor)
case Revealed:
	return fmt.Sprintf("공개 카드로 %s%s 뒤집힘",
		e.Crop.Name(), subjectParticle(e.Crop.Name()))

@ 거래와 흐름에 관한 갈래다.
@<갈래마다 기본 문장을 짓는다@>=
case TradeProposed:
	return fmt.Sprintf("%d번이 %d번에게 [%s] 주고 [%s] 받기를 제안",
		e.Actor, e.To, beanNames(e.Give), beanNames(e.Get))
case TradeRejected:
	return fmt.Sprintf("%d번이 제안을 거절", e.Actor)
case TradeAccepted:
	return fmt.Sprintf("%d번과 %d번이 [%s] 주고 [%s] 받아 교환 성사",
		e.Actor, e.To, beanNames(e.Give), beanNames(e.Get))
case DeckEmptied:
	return "덱이 바닥나 게임이 끝남"
case GiftStage:
	return "받은 콩을 심는 단계로"
case TurnPassed:
	return "턴을 넘김"

@ 결투에만 나오는 세 갈래다.
@<갈래마다 기본 문장을 짓는다@>=
case Tossed:
	return fmt.Sprintf("%d번이 %s%s 버림", e.Actor,
		e.Crop.Name(), objectParticle(e.Crop.Name()))
case Offered:
	return fmt.Sprintf("%d번이 %d번에게 [%s] 남김",
		e.Actor, e.To, beanNames(e.Give))
case Fished:
	return fmt.Sprintf("버림 더미에서 %s%s 딸려 올라옴",
		e.Crop.Name(), subjectParticle(e.Crop.Name()))

@ 조사는 앞말의 받침을 따라 갈린다. 한글 음절은 |0xAC00|부터 스물여덟 개씩
묶여 있어, 그 나머지가 $0$이면 받침이 없다. 콩 이름은 모두 ``콩''으로 끝나
받침이 있으니 늘 ``을''과 ``이''가 나오지만, 규칙으로 적어 두면 이름을 늘려도
문장이 어긋나지 않는다. (예전에는 |%s를|과 |%s가|를 박아 두어 ``커피콩를''이나
``고추콩가''라고 적었다.)
@<이벤트@>=
func hasFinal(name string) bool {
	r := []rune(name)
	if len(r) == 0 {
		return false
	}
	last := r[len(r)-1]
	if last < 0xAC00 || last > 0xD7A3 {
		return false // 한글 음절이 아니다
	}
	return (last-0xAC00)%28 != 0
}
@#
func objectParticle(name string) string {
	if hasFinal(name) {
		return "을"
	}
	return "를"
}
@#
func subjectParticle(name string) string {
	if hasFinal(name) {
		return "이"
	}
	return "가"
}

@* 액션 적용.
|Apply|는 수 하나를 받아 상태를 옮기고, 무슨 일이 있었는지 이벤트로 알린다.
불법이면 상태를 그대로 두고 오류를 돌려준다. 먼저 게임이 끝났는지와 지금이
행위자의 차례인지 확인한 뒤, 종류별 처리로 나눈다.
@<액션 적용@>=
func (s *State) Apply(a Action) ([]Event, error) {
	if s.Stage == GameOver {
		return nil, fmt.Errorf("보난자: 게임이 이미 끝남")
	}
	if a.Actor != s.ToAct() {
		return nil, fmt.Errorf("보난자: 지금은 %d번 플레이어 차례가 아님", a.Actor)
	}
	if s.Pending != nil && a.Kind != RespondTrade {
		return nil, fmt.Errorf("보난자: 먼저 거래 제안에 응답해야 함")
	}
	switch a.Kind {
	case PlantFront:
		return s.applyPlantFront(a)
	case Harvest:
		return s.applyHarvest(a)
	case BuyField:
		return s.applyBuyField(a)
	case EndPhase:
		return s.applyEndPhase(a)
	case TakeRevealed:
		return s.applyTake(a)
	case ProposeTrade:
		return s.applyPropose(a)
	case RespondTrade:
		return s.applyRespond(a)
	case PlantGift:
		return s.applyPlantGift(a)
	case TossRevealed:
		return s.applyTossRevealed(a)
	case TossHand:
		return s.applyTossHand(a)
	}
	return nil, fmt.Errorf("보난자: 알 수 없는 액션")
}

@ 맨 앞 카드 심기. 두 장을 넘겨 심을 수 없고, 심기는 밭 규칙을 따른다.
성공하면 손패에서 그 카드를 덜어내고 심은 장수를 하나 올린다.
@<액션 적용@>=
func (s *State) applyPlantFront(a Action) ([]Event, error) {
	p := s.Players[s.Active]
	if s.PlantCount >= 2 {
		return nil, fmt.Errorf("보난자: 한 턴에 두 장까지만 심을 수 있음")
	}
	if len(p.Hand) == 0 {
		return nil, fmt.Errorf("보난자: 손패가 비어 심을 수 없음")
	}
	b := p.Hand[0]
	if err := s.plant(p, a.FieldNo, b); err != nil {
		return nil, err
	}
	p.Hand = p.Hand[1:]
	s.PlantCount++
	return []Event{{Kind: Planted, Actor: a.Actor, To: NoActor,
		Crop: b, FieldNo: a.FieldNo}}, nil
}

@ 밭 거두기. 거둔 코인 수를 이벤트로 알린다.
@<액션 적용@>=
func (s *State) applyHarvest(a Action) ([]Event, error) {
	p := s.Players[a.Actor]
	b := p.Fields[a.FieldNo].Crop
	coins, err := s.harvest(p, a.FieldNo)
	if err != nil {
		return nil, err
	}
	return []Event{{Kind: Harvested, Actor: a.Actor, To: NoActor,
		Crop: b, FieldNo: a.FieldNo, Coins: coins}}, nil
}

@ 세 번째 밭 사기. 코인 세 장을 게임 밖으로 치우고 밭 한 칸을 늘린다.
@<액션 적용@>=
func (s *State) applyBuyField(a Action) ([]Event, error) {
	p := s.Players[s.Active]
	if len(p.Fields) != 2 {
		return nil, fmt.Errorf("보난자: 세 번째 밭은 한 번만 살 수 있음")
	}
	if p.Coins() < 3 {
		return nil, fmt.Errorf("보난자: 코인이 부족함")
	}
	n := len(p.Treasury)
	s.Removed = append(s.Removed, p.Treasury[n-3:]...)
	p.Treasury = p.Treasury[:n-3]
	p.Fields = append(p.Fields, Field{})
	return []Event{{Kind: BoughtField, Actor: a.Actor, To: NoActor}}, nil
}

@ 심기 단계 끝내기. 아직 한 장도 안 심었고 손패가 남았다면 거절한다.
넘어갈 때 기본 규칙은 덱에서 두 장을 뒤집어 거래 단계로 가고, 결투는 세 장을
뽑아 나누기 단계로 간다. 결투의 나누기 단계를 끝내면 그대로 턴이 넘어간다.
@<액션 적용@>=
func (s *State) applyEndPhase(a Action) ([]Event, error) {
	switch s.Stage {
	case PhasePlant:
		p := s.Players[s.Active]
		if s.PlantCount < 1 && len(p.Hand) > 0 {
			return nil, fmt.Errorf("보난자: 맨 앞 카드를 먼저 심어야 함")
		}
		if s.Rules.Duel {
			return s.beginDuelDraw()
		}
		return s.flipAndTrade()
	case PhaseTrade:
		return s.endTradePhase()
	case PhaseDuelDraw:
		return s.endDuelTurn()
	}
	return nil, fmt.Errorf("보난자: 이 단계는 끝낼 수 없음")
}

@ 공개 카드 두 장을 뒤집는다. 뒤집다가 덱이 바닥나면 게임이 끝난다.
@<액션 적용@>=
func (s *State) flipAndTrade() ([]Event, error) {
	var ev []Event
	for i := 0; i < 2; i++ {
		c, ok := s.draw()
		if !s.endIfEmpty(ok) {
			return append(ev, Event{Kind: DeckEmptied,
				Actor: NoActor, To: NoActor}), nil
		}
		s.FaceUp = append(s.FaceUp, c)
		ev = append(ev, Event{Kind: Revealed,
			Actor: NoActor, To: NoActor, Crop: c})
	}
	s.Stage = PhaseTrade
	return ev, nil
}

@ 결투 3단계 열기. 덱에서 세 장을 뽑아 상에 펼친 뒤, 버림 더미 맨 위가 그중
하나와 같은 콩이면 그것까지 끌어올린다. 끌어올린 카드도 상에 놓인 콩이 되므로
새 짝을 만들 수 있고, 그래서 맨 위가 더는 걸리지 않을 때까지 되풀이한다.
버림 더미가 두꺼울수록 한 번에 많은 콩을 쓸어 담게 되는, 결투의 별미다.
@<액션 적용@>=
func (s *State) beginDuelDraw() ([]Event, error) {
	var ev []Event
	for i := 0; i < 3; i++ {
		c, ok := s.draw()
		if !s.endIfEmpty(ok) {
			return append(ev, Event{Kind: DeckEmptied,
				Actor: NoActor, To: NoActor}), nil
		}
		s.FaceUp = append(s.FaceUp, c)
		ev = append(ev, Event{Kind: Revealed,
			Actor: NoActor, To: NoActor, Crop: c})
	}
	@<버림 더미 맨 위가 걸리는 동안 끌어올린다@>@;
	s.Stage = PhaseDuelDraw
	return ev, nil
}

@ @<버림 더미 맨 위가 걸리는 동안 끌어올린다@>=
for len(s.Discard) > 0 {
	top := s.Discard[len(s.Discard)-1]
	if !containsAll(s.FaceUp, []Card{top}) {
		break
	}
	s.Discard = s.Discard[:len(s.Discard)-1]
	s.FaceUp = append(s.FaceUp, top)
	ev = append(ev, Event{Kind: Fished, Actor: NoActor, To: NoActor, Crop: top})
}

@ 결투 3단계 끝내기, 곧 턴 넘기기다. 상에 남은 콩은 치우지 않는다---그대로
둔 채 차례만 넘어가면, 다음 사람이 턴을 열 때 그것이 곧 ``상대가 남긴 제안''이
된다. 카드를 옮기지 않고 임자만 바뀌는 셈이라, 상 위의 더미 하나로 3단계의
{\it 남긴 콩\/}과 1단계의 {\it 받은 콩\/}을 다 표현할 수 있다.
@<액션 적용@>=
func (s *State) endDuelTurn() ([]Event, error) {
	var ev []Event
	if len(s.FaceUp) > 0 {
		ev = append(ev, Event{Kind: Offered, Actor: s.Active,
			To: (s.Active + 1) % len(s.Players),
			Give: append([]Card{}, s.FaceUp...)})
	}
	s.endTurn()
	return append(ev, Event{Kind: TurnPassed, Actor: NoActor, To: NoActor}), nil
}

@ 거래 단계 끝내기. 공개 카드가 남아 있으면 거절한다. 받은 콩을 쥔 사람이
있으면 그 심기 단계로, 없으면 곧장 턴을 넘긴다.
@<액션 적용@>=
func (s *State) endTradePhase() ([]Event, error) {
	if len(s.FaceUp) > 0 {
		return nil, fmt.Errorf("보난자: 공개 카드를 모두 처리해야 함")
	}
	if s.giftsPending() {
		s.Stage = PhaseHarvestGifts
		return []Event{{Kind: GiftStage, Actor: NoActor, To: NoActor}}, nil
	}
	s.endTurn()
	return []Event{{Kind: TurnPassed, Actor: NoActor, To: NoActor}}, nil
}

@ 공개 카드를 집어 내 밭에 심고, 공개 더미에서 뺀다. 동의가 필요 없는, 활성
플레이어 자신의 처리다.
@<액션 적용@>=
func (s *State) applyTake(a Action) ([]Event, error) {
	p := s.Players[s.Active]
	if a.FaceUpNo < 0 || a.FaceUpNo >= len(s.FaceUp) {
		return nil, fmt.Errorf("보난자: 공개 카드 번호가 범위를 벗어남")
	}
	b := s.FaceUp[a.FaceUpNo]
	if err := s.plant(p, a.FieldNo, b); err != nil {
		return nil, err
	}
	s.FaceUp = removeCard(s.FaceUp, a.FaceUpNo)
	s.offerDone()
	return []Event{{Kind: PlantedFaceUp, Actor: a.Actor, To: NoActor,
		Crop: b, FieldNo: a.FieldNo}}, nil
}

@ 결투 1단계에서 상 위의 콩을 버린다. 심을 밭이 없거나 심기 싫은 콩을
치우는 길이다.
@<액션 적용@>=
func (s *State) applyTossRevealed(a Action) ([]Event, error) {
	if s.Stage != PhaseOffer {
		return nil, fmt.Errorf("보난자: 지금은 공개 카드를 버릴 수 없음")
	}
	if a.FaceUpNo < 0 || a.FaceUpNo >= len(s.FaceUp) {
		return nil, fmt.Errorf("보난자: 공개 카드 번호가 범위를 벗어남")
	}
	b := s.FaceUp[a.FaceUpNo]
	s.Discard = append(s.Discard, b)
	s.FaceUp = removeCard(s.FaceUp, a.FaceUpNo)
	s.offerDone()
	return []Event{{Kind: Tossed, Actor: a.Actor, To: NoActor, Crop: b}}, nil
}

@ 상 위의 콩을 다 처리했으면 1단계가 저절로 끝난다. 끝내는 수를 따로 두지
않았으므로, 마지막 한 알이 사라지는 자리에서 심기 단계로 옮겨 준다.
@<액션 적용@>=
func (s *State) offerDone() {
	if s.Stage == PhaseOffer && len(s.FaceUp) == 0 {
		s.Stage = PhasePlant
	}
}

@ 결투 2단계에서 손패 한 장을 버린다. 손패 {\it 아무 자리\/}에서나 뽑아낼 수
있는 유일한 곳이다---보난자에서 손패 순서를 건드리는 일은 이만큼 드물다.
턴마다 한 장까지이므로 |HandTossed|를 세워 둔다.
@<액션 적용@>=
func (s *State) applyTossHand(a Action) ([]Event, error) {
	p := s.Players[s.Active]
	if !s.Rules.Duel || s.Stage != PhasePlant {
		return nil, fmt.Errorf("보난자: 지금은 손패를 버릴 수 없음")
	}
	if s.HandTossed {
		return nil, fmt.Errorf("보난자: 한 턴에 한 장만 버릴 수 있음")
	}
	if s.PlantCount < 1 && len(p.Hand) > 0 {
		return nil, fmt.Errorf("보난자: 맨 앞 카드를 먼저 심어야 함")
	}
	if a.HandNo < 0 || a.HandNo >= len(p.Hand) {
		return nil, fmt.Errorf("보난자: 손패 번호가 범위를 벗어남")
	}
	b := p.Hand[a.HandNo]
	s.Discard = append(s.Discard, b)
	p.Hand = removeCard(p.Hand, a.HandNo)
	s.HandTossed = true
	return []Event{{Kind: Tossed, Actor: a.Actor, To: NoActor, Crop: b}}, nil
}

@ 거래 제안. 활성 플레이어가 상대에게 ``이 콩들을 줄 테니 저 콩들을 달라''고
내민다. 받을 콩이 없으면 기부다. 내주는 콩은 내 손패\slash 공개 카드에 실제로
있어야 하지만, {\it 받을 콩\/}이 상대에게 있는지는 여기서 따지지 않는다---상대
손패는 나에게 가려져 있으니, 있고 없고는 상대가 응답할 때 판가름 난다(없으면
상대는 수락할 수 없다). 이렇게 해야 제안만으로 남의 패를 넘겨짚는 정보 누출이
없다. 통과하면 제안을 걸어 두고 상대의 응답을 기다린다---그동안 |ToAct|는
상대를 가리킨다.
@<액션 적용@>=
func (s *State) applyPropose(a Action) ([]Event, error) {
	if a.To == s.Active || a.To < 0 || a.To >= len(s.Players) {
		return nil, fmt.Errorf("보난자: 거래 상대가 잘못됨")
	}
	if len(a.GiveHand)+len(a.GiveFaceUp)+len(a.GetHand) == 0 {
		return nil, fmt.Errorf("보난자: 빈 거래는 제안할 수 없음")
	}
	@<제안한 카드가 제자리에 있는지 확인한다@>@;
	s.Pending = &Proposal{From: s.Active, To: a.To,
		GiveHand:   append([]Card{}, a.GiveHand...),
		GiveFaceUp: append([]Card{}, a.GiveFaceUp...),
		GetHand:    append([]Card{}, a.GetHand...)}
	give := append(append([]Card{}, a.GiveHand...), a.GiveFaceUp...)
	return []Event{{Kind: TradeProposed, Actor: s.Active, To: a.To,
		Give: give, Get: append([]Card{}, a.GetHand...)}}, nil
}

@ 내가 내주는 두 더미가 각각 제자리(내 손패, 공개 카드)에 다중집합으로 들어
있는지 확인한다. 상대에게서 받을 콩(|GetHand|)은 여기서 확인하지 않는다---앞서
말했듯 상대의 보유 여부는 수락 시점에 가려진다.
@<제안한 카드가 제자리에 있는지 확인한다@>=
if !containsAll(s.Players[s.Active].Hand, a.GiveHand) {
	return nil, fmt.Errorf("보난자: 내 손패에 없는 콩을 줄 수 없음")
}
if !containsAll(s.FaceUp, a.GiveFaceUp) {
	return nil, fmt.Errorf("보난자: 공개되지 않은 콩을 줄 수 없음")
}

@ 응답. 거절하면 제안을 지우고 활성 플레이어에게 차례가 돌아간다. 수락하면
카드를 옮긴다.
@<액션 적용@>=
func (s *State) applyRespond(a Action) ([]Event, error) {
	pr := s.Pending
	if pr == nil {
		return nil, fmt.Errorf("보난자: 응답할 제안이 없음")
	}
	if !a.Accept {
		s.Pending = nil
		return []Event{{Kind: TradeRejected, Actor: a.Actor, To: NoActor}}, nil
	}
	@<제안대로 카드를 옮긴다@>@;
}

@ 수락 처리. 여기서 비로소 세 더미가 다 갖춰졌는지 확인한다---특히 상대가
요구받은 콩을 실제로 쥐고 있는지가 이 자리에서 판가름 난다. 하나라도 모자라면
{\it 상태를 건드리지 않고\/} 오류만 돌려준다(제안은 그대로 남으니 상대는 거절로
물릴 수 있고, 서버도 헛되이 알리지 않는다). 다 갖춰졌으면 세 더미를 각 출처에서
빼서 받는 쪽으로 옮긴다. 거래로 받은 콩은 양쪽 모두 |Acquired|로 가, 다음 단계에서
즉시 심어진다.
@<제안대로 카드를 옮긴다@>=
from, to := s.Players[pr.From], s.Players[pr.To]
if !containsAll(from.Hand, pr.GiveHand) ||
	!containsAll(s.FaceUp, pr.GiveFaceUp) ||
	!containsAll(to.Hand, pr.GetHand) {
	return nil, fmt.Errorf("보난자: 요구한 콩이 상대에게 없어 수락할 수 없음")
}
from.Hand = removeBeans(from.Hand, pr.GiveHand)
s.FaceUp = removeBeans(s.FaceUp, pr.GiveFaceUp)
to.Hand = removeBeans(to.Hand, pr.GetHand)
to.Acquired = append(to.Acquired, pr.GiveHand...)
to.Acquired = append(to.Acquired, pr.GiveFaceUp...)
from.Acquired = append(from.Acquired, pr.GetHand...)
s.Pending = nil
give := append(append([]Card{}, pr.GiveHand...), pr.GiveFaceUp...)
return []Event{{Kind: TradeAccepted, Actor: pr.From, To: pr.To,
	Give: give, Get: append([]Card{}, pr.GetHand...)}}, nil

@ 두 다중집합 도우미다. |containsAll|은 |pool|이 |want|를 개수까지 담는지 보고,
|removeBeans|는 |pool|에서 |drop|의 콩을 값으로 하나씩 빼낸다.
@<액션 적용@>=
func containsAll(pool, want []Card) bool {
	cnt := make(map[Card]int)
	for _, c := range pool {
		cnt[c]++
	}
	for _, c := range want {
		cnt[c]--
		if cnt[c] < 0 {
			return false
		}
	}
	return true
}

func removeBeans(pool, drop []Card) []Card {
	out := append([]Card{}, pool...)
	for _, d := range drop {
		for i, c := range out {
			if c == d {
				out = append(out[:i], out[i+1:]...)
				break
			}
		}
	}
	return out
}

@ 받은 콩 심기. 못 심은 콩의 맨 앞 한 알을 밭에 놓는다. 그 사람의 콩을 다
심었고 아무도 남지 않았으면 턴을 넘긴다.
@<액션 적용@>=
func (s *State) applyPlantGift(a Action) ([]Event, error) {
	p := s.Players[a.Actor]
	b := p.Acquired[0]
	if err := s.plant(p, a.FieldNo, b); err != nil {
		return nil, err
	}
	p.Acquired = p.Acquired[1:]
	ev := []Event{{Kind: PlantedGift, Actor: a.Actor, To: NoActor,
		Crop: b, FieldNo: a.FieldNo}}
	if !s.giftsPending() {
		s.endTurn()
		ev = append(ev, Event{Kind: TurnPassed, Actor: NoActor, To: NoActor})
	}
	return ev, nil
}

@ 슬라이스에서 카드 한 장을 위치로 빼는 잔손질이다. 순서는 유지한다.
@<액션 적용@>=
func removeCard(cs []Card, i int) []Card {
	return append(cs[:i:i], cs[i+1:]...)
}

@* 점수와 불변식.
게임이 끝나면 각자 손에 쥔 코인에, 아직 밭에 남은 콩을 모두 거두었을 때의
코인을 더해 최종 점수를 낸다. 상태를 건드리지 않고 계산만 한다.
@<점수와 불변식@>=
func (s *State) Over() bool { return s.Stage == GameOver }

func (s *State) Scores() []int {
	sc := make([]int, len(s.Players))
	for i, p := range s.Players {
		sc[i] = p.Coins()
		for _, f := range p.Fields {
			sc[i] += f.Crop.Coins(f.Count)
		}
	}
	return sc
}

@ 엔진이 규칙대로 도는지 지키는 파수꾼이 카드 보존 불변식이다. 게임 어디에
있든 카드는 언제나 정확히 154장이어야 한다. 시험은 매 수 뒤에 이것을 부른다.
@<점수와 불변식@>=
func (s *State) countCards() int {
	n := len(s.Deck) + len(s.Discard) + len(s.FaceUp) + len(s.Removed)
	for _, p := range s.Players {
		n += len(p.Hand) + len(p.Acquired) + len(p.Treasury)
		for _, f := range p.Fields {
			n += f.Count
		}
	}
	return n
}

func (s *State) Check() error {
	if n := s.countCards(); n != TotalCards {
		return fmt.Errorf("보난자: 카드 보존 위반, %d장(154장이어야 함)", n)
	}
	return nil
}

@* 플레이어 뷰.
엔진은 게임의 모든 것을 알지만, 클라이언트에게는 그가 볼 수 있는 것만 보내야
한다. 남의 손패와 덱 속은 가린다. |View|는 한 플레이어의 시점으로 상태를
추려, 그대로 JSON으로 실어 보낼 수 있는 값으로 만든다. 웹 서버는 이 하나로
서버와 클라이언트의 경계를 긋는다---서버는 |State|를 쥐고, 바깥으로는 |View|만
나간다.

@ 뷰의 조각 타입들이다. 밭과 코인, 공개 카드는 모두에게 보이고, 손패는 본인
것만 카드까지 보이며 남의 것은 장수만 보인다. 콩은 정수 식별자로 실어 보내고,
이름\slash 장수\slash 콩미터 같은 고정 정보는 |Catalog|로 따로 한 번만 받는다.
@<플레이어 뷰@>=
type FieldView struct {
	Crop  Bean `json:"bean"`  // Count가 0이면 빈 밭이라 의미 없음
	Count int  `json:"count"`
}

type PlayerView struct {
	Index     int         `json:"index"`
	IsYou     bool        `json:"isYou"`
	Fields    []FieldView `json:"fields"`
	Coins     int         `json:"coins"`
	Acquired  []Bean      `json:"acquired"`
	HandCount int         `json:"handCount"`
	Hand      []Bean      `json:"hand,omitempty"` // 본인만 채워진다
}

@ 진행 중인 거래 제안도 뷰에 담는다. 보난자의 거래는 공개 협상이므로 무엇을
주고받는지는 모두가 안다.
@<플레이어 뷰@>=
type ProposalView struct {
	From       int    `json:"from"`
	To         int    `json:"to"`
	GiveHand   []Bean `json:"giveHand"`
	GiveFaceUp []Bean `json:"giveFaceUp"`
	GetHand    []Bean `json:"getHand"`
}

@ 뷰 전체다. 공개 상태에 더해, 이 뷰 주인이 지금 둘 수 있는 합법수(|Legal|)까지
실어 준다. 클라이언트는 이 하나로 화면을 그리고 버튼을 만든다.
@<플레이어 뷰@>=
type View struct {
	You          int           `json:"you"`
	Active       int           `json:"active"`
	ToAct        int           `json:"toAct"`
	Stage        Phase         `json:"phase"`
	PhaseName    string        `json:"phaseName"`
	Players      []PlayerView  `json:"players"`
	FaceUp       []Bean        `json:"faceUp"`
	DeckCount    int           `json:"deckCount"`
	DiscardCount int           `json:"discardCount"`
	Pending      *ProposalView `json:"pending,omitempty"`
	Legal        []Action      `json:"legal"`
	Over         bool          `json:"over"`
	Scores       []int         `json:"scores,omitempty"`
}

@ |View|는 한 플레이어의 시점으로 상태를 추린다. 공개 정보를 채우고, 각
플레이어를 시점에 맞게 가리고, 대기 중인 제안과 (끝났다면) 점수를 붙인다.
@<플레이어 뷰@>=
func (s *State) View(player int) View {
	v := View{
		You:          player,
		Active:       s.Active,
		ToAct:        s.ToAct(),
		Stage:        s.Stage,
		PhaseName:    s.Stage.String(),
		FaceUp:       append([]Bean{}, s.FaceUp...),
		DeckCount:    len(s.Deck),
		DiscardCount: len(s.Discard),
		Legal:        s.Legal(player),
		Over:         s.Over(),
	}
	for i, p := range s.Players {
		v.Players = append(v.Players, s.playerView(i, p, player))
	}
	@<대기 제안과 점수를 붙인다@>@;
	return v
}

@ 대기 중인 제안이 있으면 공개 형태로 옮기고, 게임이 끝났으면 점수를 담는다.
@<대기 제안과 점수를 붙인다@>=
if s.Pending != nil {
	pr := s.Pending
	v.Pending = &ProposalView{From: pr.From, To: pr.To,
		GiveHand:   append([]Bean{}, pr.GiveHand...),
		GiveFaceUp: append([]Bean{}, pr.GiveFaceUp...),
		GetHand:    append([]Bean{}, pr.GetHand...)}
}
if s.Over() {
	v.Scores = s.Scores()
}

@ 플레이어 하나를 시점에 맞게 가린다. 밭\slash 코인\slash 받은 콩\slash 손패
장수는 누구에게나 보이지만, 손패 카드는 본인에게만 채워 준다.
@<플레이어 뷰@>=
func (s *State) playerView(i int, p *Player, viewer int) PlayerView {
	pv := PlayerView{
		Index:     i,
		IsYou:     i == viewer,
		Coins:     p.Coins(),
		HandCount: len(p.Hand),
		Acquired:  append([]Bean{}, p.Acquired...),
	}
	for _, f := range p.Fields {
		pv.Fields = append(pv.Fields, FieldView{Crop: f.Crop, Count: f.Count})
	}
	if i == viewer {
		pv.Hand = append([]Bean{}, p.Hand...)
	}
	return pv
}

@ 뷰를 곧장 JSON으로 실어 준다. 웹 서버는 이 바이트열을 클라이언트에 보낸다.
@<플레이어 뷰@>=
func (s *State) ViewJSON(player int) ([]byte, error) {
	return json.Marshal(s.View(player))
}

@ 콩의 고정 정보(이름\slash 장수\slash 콩미터)는 게임 내내 바뀌지 않으므로,
클라이언트가 처음에 한 번만 받아 두면 된다. |Catalog|가 그 표를 내준다.
@<플레이어 뷰@>=
type BeanInfoView struct {
	ID    Bean   `json:"id"`
	Name  string `json:"name"`
	Count int    `json:"count"`
	Meter [4]int `json:"meter"`
}

func Catalog() []BeanInfoView {
	out := make([]BeanInfoView, 0, NumBeans)
	for b := Bean(0); b < NumBeans; b++ {
		info := beanTable[b]
		out = append(out, BeanInfoView{b, info.Name, info.Count, info.Meter})
	}
	return out
}

@* 시험.
시험은 패키지 안에서 돌며 내부 함수까지 들여다본다. 무작위성은 재현
가능하도록 씨앗을 고정한 |math/rand/v2|의 PCG를 쓴다.
@(bohnanza_test.go@>=
package bohnanza

import (
	"encoding/json"
	"math/rand/v2"
	"testing"
)

@<덱 구성 시험@>@;
@<콩미터 시험@>@;
@<양방향 거래 시험@>@;
@<다장 거래 시험@>@;
@<뷰 가림 시험@>@;
@<수확 제한 시험@>@;
@<변형 차림 시험@>@;
@<보충 시험@>@;
@<결투 시험@>@;
@<무작위 완주 시험@>@;

@ 덱은 정확히 154장이어야 하고, 콩미터 테이블의 장수 합도 154여야 한다.
@<덱 구성 시험@>=
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

@ 콩미터 몇 개를 손으로 확인한다: 장수가 임계값에 못 미치면 코인 0, 넘어서면
해당 코인이다.
@<콩미터 시험@>=
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

@ 양방향 거래를 콕 집어 확인한다. 0번이 커피콩을 주고 1번의 강낭콩을 받는
1대1 교환을 제안하고, 1번이 수락하면 두 사람의 ``받은 콩''에 각각 상대의
콩이 들어가고 손패에서는 빠져 있어야 한다. |New| 대신 작은 상태를 손으로
차려---난수가 필요 없다---거래만 떼어 본다.
@<양방향 거래 시험@>=
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
	@<교환 결과를 확인한다@>@;
}

@ 교환 뒤: 0번은 강낭콩을, 1번은 커피콩을 받은 콩으로 가지고, 각자 손패에서
그 카드가 빠지고, 대기 제안은 사라져야 한다.
@<교환 결과를 확인한다@>=
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

@ 자유형 다장 거래를 본다. 0번이 커피 두 장을 주고 상대의 강낭콩과 고추콩을
받는 (2대2) 거래를 제안해 성사시키면, 양쪽 ``받은 콩''과 손패가 맞아야 한다.
@<다장 거래 시험@>=
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

@ 상대에게 없는 콩을 달라는 제안은 {\it 통과\/}하되(상대 패는 가려져 있으니),
상대가 수락하려 하면 실패하고 상태는 그대로여야 한다. 그 뒤 상대는 거절로
깔끔히 물릴 수 있어야 한다.
@<다장 거래 시험@>=
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

@ 뷰가 남의 손패와 덱 속을 제대로 가리는지 본다. 0번 시점의 뷰에서 0번의
손패는 카드까지 보이되, 남의 손패는 장수만 보이고 카드는 비어 있어야 한다.
JSON으로 실어 보냈다 되받아도 이 가림이 유지되어야 한다---서버가 클라이언트에
남의 패를 흘리면 안 되기 때문이다.
@<뷰 가림 시험@>=
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
	@<JSON 왕복 뒤에도 가림이 유지되는지 본다@>@;
}

@ JSON으로 부호화했다 복호화한 뒤에도 남의 손패는 비어 있어야 하고, 콩 도감은
열한 종류에 합이 154장이어야 한다.
@<JSON 왕복 뒤에도 가림이 유지되는지 본다@>=
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

@ 한 장짜리 밭 수확 제한을 콕 집어 본다. 0번 밭이 한 장, 1번 밭이 두 장이면
0번은 못 거두고 1번만 거둘 수 있다. 큰 밭을 거두고 나면 두 장 이상인 밭이
사라져 0번도 거둘 수 있게 된다.
@<수확 제한 시험@>=
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

@ 인원마다 판이 제대로 차려지는지 본다. 덱 장수는 154에서 뺀 콩과 나눠 준
손패를 덜어낸 만큼이어야 하고, 밭 칸수는 변형이 정한 대로여야 하며, 뺀 콩은
|Removed|에 그대로 있어야 한다---그래야 카드 보존이 154장으로 성립한다.
@<변형 차림 시험@>=
func TestVariantSetup(t *testing.T) {
	cases := []struct{ players, deck, removed, fields int }{
		{2, 144 - 10, 10, 3}, // 정원콩 6 + 카카오콩 4를 뺀다
		{3, 150 - 15, 4, 3},  // 카카오콩 4를 뺀다
		{4, 154 - 20, 0, 2},  // 기본 규칙: 아무것도 안 뺀다
	}
	for _, c := range cases {
		s, err := New(c.players, 7)
		if err != nil {
			t.Fatal(err)
		}
		@<차림이 표대로인지 본다@>@;
	}
}

@ 뺀 콩이 손패로 새어 들지 않았는지까지 확인한다---덱을 쌓을 때 갈라 담으므로
샐 수 없어야 하지만, 그 갈래가 곧 변형의 전부이니 못 박아 둔다.
@<차림이 표대로인지 본다@>=
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

@ 세 번째 밭 사기는 4인에서만 나와야 한다. $2\sim3$인은 밭 3칸으로 시작하는
대신 더 사지 못한다.
@<변형 차림 시험@>=
func TestFieldBuyingByVariant(t *testing.T) {
	for _, c := range []struct {
		players int
		want    bool
	}{{2, false}, {3, false}, {4, true}} {
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

@ 보충은 인원마다 모양이 다르다. 3인은 전원이 한 장씩 돌고, 4인은 활성
플레이어 혼자 세 장을 뽑는다.
@<보충 시험@>=
func TestRefillByVariant(t *testing.T) {
	s3, _ := New(3, 5)
	before := handSizes(s3)
	s3.endTurn()
	for i, p := range s3.Players {
		if len(p.Hand) != before[i]+1 {
			t.Errorf("3인 %d번: %d→%d장, 한 장씩 기대",
				i, before[i], len(p.Hand))
		}
	}
	@<4인은 활성 플레이어만 세 장인지 본다@>@;
}

@ @<4인은 활성 플레이어만 세 장인지 본다@>=
s4, _ := New(4, 5)
was := handSizes(s4)
s4.endTurn()
for i, p := range s4.Players {
	want := was[i]
	if i == 0 {
		want += 3
	}
	if len(p.Hand) != want {
		t.Errorf("4인 %d번: %d장, %d장 기대", i, len(p.Hand), want)
	}
}

@ @<보충 시험@>=
func handSizes(s *State) []int {
	n := make([]int, len(s.Players))
	for i, p := range s.Players {
		n[i] = len(p.Hand)
	}
	return n
}

@ 결투에서만 나오는 손패 버리기다. 자리마다 하나씩 수가 나오고, 버린 카드는
버림 더미로 가며, 한 턴에 두 번째는 거절당해야 한다.
@<결투 시험@>=
func TestDuelTossHand(t *testing.T) {
	s, _ := New(2, 11)
	p := s.Players[0]
	if _, err := s.Apply(Action{Kind: PlantFront, Actor: 0, FieldNo: 0}); err != nil {
		t.Fatal(err) // 한 장 심어야 버릴 수 있다
	}
	@<버리기 수가 손패 자리마다 나오는지 본다@>@;
	@<한 장 버리고, 두 번째는 막히는지 본다@>@;
}

@ @<버리기 수가 손패 자리마다 나오는지 본다@>=
tosses := 0
for _, a := range s.Legal(0) {
	if a.Kind == TossHand {
		tosses++
	}
}
if tosses != len(p.Hand) {
	t.Errorf("버리기 수 %d개, 손패 %d장", tosses, len(p.Hand))
}

@ @<한 장 버리고, 두 번째는 막히는지 본다@>=
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

@ 결투의 턴 흐름을 통째로 본다. 시작 플레이어는 상 위에 아무것도 없으므로
|PhaseOffer|를 건너뛰어야 하고, 심기를 끝내면 세 장이 뒤집혀 나누기 단계로
가야 하며, 그 단계를 끝내면 남은 콩이 그대로 다음 사람의 받은 제안이 되어야
한다---카드가 옮겨 다니지 않고 임자만 바뀌는지가 핵심이다.
@<결투 시험@>=
func TestDuelTurnFlow(t *testing.T) {
	s, _ := New(2, 3)
	if s.Stage != PhasePlant {
		t.Fatalf("시작 단계가 %v, 시작 플레이어는 제안을 건너뛰어야 함", s.Stage)
	}
	mustApply(t, s, Action{Kind: PlantFront, Actor: 0, FieldNo: 0})
	mustApply(t, s, Action{Kind: EndPhase, Actor: 0})
	@<세 장이 뒤집혀 나누기 단계인지 본다@>@;
	@<남긴 콩이 상대의 받은 제안이 되는지 본다@>@;
}

@ @<세 장이 뒤집혀 나누기 단계인지 본다@>=
if s.Stage != PhaseDuelDraw {
	t.Fatalf("단계가 %v, 뽑아 나누기 기대", s.Stage)
}
if len(s.FaceUp) < 3 {
	t.Fatalf("상 위에 %d장, 적어도 3장 기대", len(s.FaceUp))
}

@ @<남긴 콩이 상대의 받은 제안이 되는지 본다@>=
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

@ @<결투 시험@>=
func mustApply(t *testing.T, s *State, a Action) {
	t.Helper()
	if _, err := s.Apply(a); err != nil {
		t.Fatalf("%v: %v", a, err)
	}
}

@ 가장 든든한 시험은 무작위 완주다. 합법수 가운데 하나를 무작위로 골라 게임을
끝까지 몰고 가며, 매 수 뒤에 카드 보존 불변식이 깨지지 않는지 본다. 여러
씨앗과 인원으로 수천 판을 돌리면 상태 기계의 막다른 골목과 규칙 구멍이 드러난다.
@<무작위 완주 시험@>=
func TestRandomPlaythrough(t *testing.T) {
	for seed := uint64(0); seed < 200; seed++ {
		players := 2 + int(seed%3)
		s, err := New(players, seed)
		if err != nil {
			t.Fatal(err)
		}
		rng := rand.New(rand.NewPCG(seed, 12345))
		@<무작위로 한 판을 끝까지 둔다@>@;
	}
}

@ 한 수를 둘 때마다 행위자의 합법수를 받아 하나를 골라 적용한다. 합법수가
비면 게임이 막힌 것이므로 실패로 본다. 무한 루프를 막으려 수에 상한을 둔다.
@<무작위로 한 판을 끝까지 둔다@>=
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

@* 색인.
