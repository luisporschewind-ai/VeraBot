"""Shared, hand-calculated fixtures; no production database or model."""
import copy
import json
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from verabot.services.tetris_sessions import rules
FIXTURES = Path(__file__).resolve().parents[3] / 'docs/contracts/tetris-v2-fixtures.json'

class RulesTests(unittest.TestCase):
    def test_shared_fixtures(self):
        for case in json.loads(FIXTURES.read_text())['cases']:
            with self.subTest(case=case['name']):
                state = rules.restore(case['initial'])
                events = []
                for step in case['steps']:
                    events += rules.apply(state, step['action']) if 'action' in step else rules.advance(state, step['elapsed'])
                self.assertEqual(rules.snapshot(state), case['expectedSnapshot'])
                self.assertEqual(events, case['expectedEvents'])

    def test_invalid_snapshots_and_actions(self):
        initial = json.loads(FIXTURES.read_text())['cases'][0]['initial']
        for key, value in [('board', [0]*199), ('rngState', 0), ('unexpected', 2), ('phase', 'fake'), ('score', True), ('ruleVersion','legacy-1')]:
            with self.subTest(key=key), self.assertRaises(rules.InvalidSnapshot):
                rules.restore({**initial, key:value})
        invalid = copy.deepcopy(initial)
        invalid.update(phase='over')
        invalid['active']['rotation']=-1
        with self.assertRaises(rules.InvalidSnapshot): rules.restore(invalid)
        with self.assertRaises(ValueError): rules.apply(rules.restore(initial), 'teleport')

    def test_seven_bag_is_deterministic_and_has_no_repeat_inside_bag(self):
        fixtures=json.loads(FIXTURES.read_text())
        a,b = rules.new(42),rules.new(42)
        self.assertEqual(rules.snapshot(a),fixtures['seed42Initial'])
        rules.apply(a,'start');rules.apply(b,'start')
        pieces=[]
        for _ in range(21):
            pieces.append(a.state['active']['kind'])
            rules.apply(a,'hardDrop');rules.apply(b,'hardDrop')
            a.state['board']=[0]*200;b.state['board']=[0]*200
        self.assertEqual(pieces,fixtures['seed42BagSequence'])
        self.assertEqual(rules.snapshot(a),rules.snapshot(b))
        for offset in (0,7,14):self.assertEqual(set(pieces[offset:offset+7]),set(range(1,8)))

if __name__=='__main__': unittest.main()
