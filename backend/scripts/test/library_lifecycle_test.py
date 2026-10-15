import unittest
from library_test_support import setup, attached, db, repo

class LifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.cli,cls.h,cls.uid,_,_,cls.bots=setup()
    def test_clear_chat_keeps_original(self):
        aid,mid=attached(self.uid,self.bots[0]); original=repo.get(self.uid,aid)
        response=self.cli.delete(f'/api/bots/{self.bots[0]}/messages',headers=self.h)
        self.assertEqual(response.status_code,200,response.text)
        from verabot.services import library
        item=library.get_item(self.uid,aid)
        self.assertTrue(repo.get_store().exists(original['storage_key']))
        self.assertFalse(item['sources'][0]['message_available'])
    def test_unlink_then_reingest_stays_unlinked(self):
        from verabot.services import library
        aid,mid=attached(self.uid,self.bots[0])
        library.link_bot(self.uid,aid,self.bots[1]); library.unlink_bot(self.uid,aid,self.bots[0])
        with db.tx() as c: library.ingest_attachment(c,user_id=self.uid,attachment_id=aid,source_kind='private',source_id=self.bots[0],bot_id=self.bots[0])
        self.assertEqual(library.get_item(self.uid,aid)['bot_ids'],[self.bots[1]])
        library.link_bot(self.uid,aid,self.bots[0])
        self.assertEqual(len(library.get_item(self.uid,aid)['bot_ids']),2)
    def test_delete_then_reingest_stays_deleted(self):
        from verabot.services import library
        aid,mid=attached(self.uid,self.bots[0]); library.delete_item(self.uid,aid)
        with db.tx() as c: library.ingest_attachment(c,user_id=self.uid,attachment_id=aid,source_kind='private',source_id=self.bots[0],bot_id=self.bots[0])
        with self.assertRaises(library.LibraryError): library.get_item(self.uid,aid)
        response=self.cli.get(f'/api/attachments/{aid}/content',headers=self.h)
        self.assertEqual(response.status_code,404)
    def test_group_files_survive_clear_without_bot_access(self):
        from verabot.db import group_store, group_execution_store
        from verabot.services import library
        from uuid import uuid4
        group=group_store.create_group(self.uid,"Library group",self.bots)
        att=repo.create_file(self.uid,None,b"group original","group.txt")
        group_execution_store.create_input(self.uid,group["id"],dict(client_request_id=str(uuid4()),message="group document",attachment_ids=[att["id"]],everyone=False))
        item=library.get_item(self.uid,att["id"])
        self.assertEqual(item["bot_ids"],[])
        self.assertEqual(item["sources"][0]["kind"],"group")
        group_store.delete_group(self.uid,group["id"],clear_only=True)
        self.assertEqual(library.get_item(self.uid,att["id"])["availability"],"available")

    def test_delete_bot_preserves_other_links(self):
        from verabot.services import library
        bot=self.cli.post('/api/bots',headers=self.h,json={'name':'Temporary'}).json()['id']
        aid,_=attached(self.uid,bot); library.link_bot(self.uid,aid,self.bots[1])
        self.assertEqual(self.cli.delete(f'/api/bots/{bot}',headers=self.h).status_code,200)
        item=library.get_item(self.uid,aid)
        self.assertEqual(item['bot_ids'],[self.bots[1]])
        self.assertEqual(item['availability'],'available')

if __name__=='__main__': unittest.main()
