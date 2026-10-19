"""Every planned action is replayed through real rules with the original hidden bag."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from verabot.services.tetris_sessions import planner,rules

class PlannerTests(unittest.TestCase):
    def game(self):
        game=rules.new(42);rules.apply(game,'start');return game
    def test_reachable_timed_actions_replay_without_board_teleportation(self):
        game=self.game();before=rules.snapshot(game)
        public=planner.PlannerState.from_snapshot(before,version=8,epoch=3)
        result=planner.plan(public,max_nodes=200,budget_ms=20,_clock=lambda:0)
        self.assertEqual(result.version,8);self.assertEqual(result.controlEpoch,3)
        self.assertTrue(result.actions)
        self.assertEqual(rules.snapshot(game),before)
        times=[action.earliestLogicalTimeMs for action in result.actions]
        self.assertTrue(all(b-a>=40 for a,b in zip(times,times[1:])))
        for action in result.actions:
            rules.advance(game,action.earliestLogicalTimeMs-game.state['logicalTimeMs'])
            events=rules.apply(game,action.action)
            self.assertTrue(events,action)
        self.assertGreater(game.state['lockedPieces'],before['lockedPieces'])
    def test_hidden_sequence_never_enters_planner_state(self):
        before=rules.snapshot(self.game())
        first=planner.PlannerState.from_snapshot(before,version=1,epoch=1)
        second=planner.PlannerState.from_snapshot({**before,'bag':[7,6,5],'rngState':123},version=1,epoch=1)
        self.assertEqual(first,second)
        self.assertNotIn('bag',vars(first));self.assertNotIn('rngState',vars(first))
        self.assertEqual(planner.plan(first,max_nodes=100,_clock=lambda:0).actions,planner.plan(second,max_nodes=100,_clock=lambda:0).actions)
    def test_budget_exhaustion_returns_legal_best_candidate(self):
        public=planner.PlannerState.from_snapshot(rules.snapshot(self.game()),version=1,epoch=1)
        result=planner.plan(public,max_nodes=1,_clock=lambda:0)
        self.assertLessEqual(result.nodes,1)
        self.assertEqual(result.actions[-1].action,'hardDrop')
        calls=iter([0,.021,.022])
        result=planner.plan(public,_clock=lambda:next(calls,.023))
        self.assertTrue(result.budgetExhausted)
        self.assertLessEqual(result.nodes,1)
    def test_fixed_budget_tie_break_is_stable(self):
        public=planner.PlannerState.from_snapshot(rules.snapshot(self.game()),version=1,epoch=1)
        first=planner.plan(public,max_nodes=200,_clock=lambda:0)
        self.assertEqual(first,planner.plan(public,max_nodes=200,_clock=lambda:0))

if __name__=='__main__':unittest.main()
