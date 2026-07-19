//line server/server.w:754
package main

import (
	"sync"
	"testing"
	"time"

	bz "github.com/sjnam/bohnanza"
)

//line server/server.w:769
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

//line server/server.w:789
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

//line server/server.w:783

//line server/server.w:825
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
	busy(func() { g.chat(0, "안녕") })
	busy(func() { g.unregister(g.register(0)) })
	busy(func() { h.reap(time.Now()) })
	busy(func() { _, _ = h.create(2, 1, 1) })
	wg.Wait()

//line server/server.w:784
}
