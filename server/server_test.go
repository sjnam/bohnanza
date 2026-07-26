//line server/server.w:841
package main

import (
	"sync"
	"testing"
	"time"

	bz "github.com/sjnam/bohnanza/engine"
)

//line server/server.w:857
func TestBotGoroutineRace(t *testing.T) {
	h := newHub()
	code, err := h.create(3, 2, 42)
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := h.join(code, "철수"); err != nil {
		t.Fatal(err)
	}
	g := h.get(code)
	if g == nil {
		t.Fatal("방이 없음")
	}

//line server/server.w:877
	for i := 0; i < 40; i++ {
		g.mu.Lock()
		done := g.state.Over() || g.state.ToAct() != 0
		var acts []bz.Action
		if !done {
			acts = g.state.Legal(0)
		}
		g.mu.Unlock()
		if done {
			break
		}
		pick := acts[0]
		for _, a := range acts {
			if a.Kind == bz.EndPhase {
				pick = a
				break
			}
			if a.Kind != bz.ProposeTrade {
				pick = a
			}
		}
		if _, err := g.apply(pick); err != nil {
			break
		}
	}

//line server/server.w:871

//line server/server.w:913
	var wg sync.WaitGroup
	stop := make(chan struct{})
	time.AfterFunc(2*time.Second, func() { close(stop) })
	busy := func(f func()) {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for {
				select {
				case <-stop:
					return
				default:
				}
				f()
				time.Sleep(time.Millisecond)
			}
		}()
	}
	busy(func() { g.view(0) })
	busy(func() { g.chat(0, "", "안녕") })
	busy(func() { g.unregister(g.register(0)) })
	busy(func() { h.reap(time.Now()) })
	busy(func() { _, _ = h.create(2, 1, 1) })
	wg.Wait()

//line server/server.w:872
}

//line server/server.w:943
func TestSpectatorTakesNoSeat(t *testing.T) {
	h := newHub()
	code, err := h.create(2, 1, 7) // 자리 둘 가운데 하나는 봇
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := h.join(code, "철수"); err != nil {
		t.Fatal(err) // 남은 사람 자리 하나를 채운다
	}

//line server/server.w:959
	if _, _, err := h.join(code, "늦은이"); err == nil {
		t.Error("자리가 다 찼는데 참가가 성공함")
	}
	tok, err := h.watch(code, "구경꾼")
	if err != nil {
		t.Fatalf("가득 찬 방에 관전이 막힘: %v", err)
	}
	g, player, ok := h.session(tok)
	if !ok || player != bz.Spectator {
		t.Fatalf("관전 세션이 이상함: player=%d ok=%v", player, ok)
	}
	if h.sessionName(tok) != "구경꾼" {
		t.Errorf("관전자 이름이 %q", h.sessionName(tok))
	}

//line server/server.w:953

//line server/server.w:977
	sv, pv := g.view(player), g.view(0)
	if len(pv.Players[0].Hand) == 0 {
		t.Error("자리 있는 이가 제 손패를 못 봄")
	}
	for i, p := range sv.Players {
		if p.Hand != nil {
			t.Errorf("관전자에게 %d번 손패가 보임: %v", i, p.Hand)
		}
	}
	if sv.Legal != nil {
		t.Errorf("관전자에게 둘 수 있는 수가 있음: %v", sv.Legal)
	}

//line server/server.w:954
}
