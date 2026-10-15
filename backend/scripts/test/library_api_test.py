import unittest
from library_test_support import setup, attached

class LibraryAPITests(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.cli,cls.h,cls.uid,cls.h2,_,cls.bots=setup()
    def upload(self,key='new-upload'):
        return self.cli.post('/api/library/items',headers={**self.h,'Idempotency-Key':key},files={'file':('notes.txt',b'unique searchable content','text/plain')})
    def test_owner_can_read_unlinked_item(self):
        r=self.upload(); self.assertEqual(r.status_code,201,r.text)
        item=r.json(); self.assertEqual(item['bot_ids'],[]); self.assertEqual(len(item['sha256']),64)
        self.assertEqual(self.cli.get('/api/library/items/'+item['id']+'/content',headers=self.h).content,b'unique searchable content')
        self.assertEqual(self.cli.get('/api/library/items/'+item['id'],headers=self.h2).status_code,404)
    def test_text_original_keeps_bom_bytes(self):
        data=b"\xef\xbb\xbforiginal"
        response=self.cli.post("/api/library/items",headers={**self.h,"Idempotency-Key":"bom"},files={"file":("bom.txt",data,"text/plain")})
        self.assertEqual(response.status_code,201,response.text)
        self.assertEqual(self.cli.get("/api/library/items/"+response.json()["id"]+"/content",headers=self.h).content,data)

    def test_upload_retry_creates_one_item(self):
        first=self.upload('retry'); second=self.upload('retry')
        self.assertEqual(first.status_code,201,first.text); self.assertEqual(first.json()['id'],second.json()['id'])
    def test_snapshot_pagination_rejects_revision_change(self):
        attached(self.uid,self.bots[0]); attached(self.uid,self.bots[1])
        page=self.cli.get('/api/library/items?limit=1',headers=self.h)
        self.assertEqual(page.status_code,200,page.text)
        self.assertIsNotNone(page.json()['next_cursor'])
        attached(self.uid,self.bots[0])
        next_page=self.cli.get('/api/library/items',params={'cursor':page.json()['next_cursor'],'limit':1},headers=self.h)
        self.assertEqual(next_page.status_code,409,next_page.text)
    def test_delete_is_visible_in_changes(self):
        aid,_=attached(self.uid,self.bots[0]); before=self.cli.get('/api/library/items',headers=self.h)
        self.assertEqual(before.status_code,200,before.text)
        revision=before.json()['snapshot_revision']
        self.assertEqual(self.cli.delete('/api/library/items/'+aid,headers=self.h).status_code,200)
        delta=self.cli.get('/api/library/changes',params={'after_revision':revision},headers=self.h).json()
        self.assertIn(aid,delta['removed_ids'])
    def test_source_clear_and_bot_removal_are_in_changes(self):
        from verabot.db import library_store
        from verabot import db
        aid, mid = attached(self.uid,self.bots[0])
        with db.tx() as c: before=library_store.revision(c,self.uid)
        db.delete_message(self.uid,self.bots[0],mid)
        delta=self.cli.get("/api/library/changes",params={"after_revision":before},headers=self.h).json()
        self.assertIn(aid,[i["id"] for i in delta["upserts"]])

    def test_search_returns_filename_and_extracted_text_matches(self):
        r=self.upload('search'); self.assertEqual(r.status_code,201,r.text)
        result=self.cli.get('/api/library/items?q=searchable',headers=self.h).json()
        self.assertIn(r.json()['id'],[i['id'] for i in result['items']])

if __name__=='__main__': unittest.main()
