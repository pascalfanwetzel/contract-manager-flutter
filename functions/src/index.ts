import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

admin.initializeApp();

// Firestore-triggered GC: whenever an attachments_index entry is written and the
// refcount <= 0 (or the doc is deleted), remove the corresponding blob from Storage.
// Keeps client delete blocked while providing immediate cleanup without Scheduler.
export const attachmentIndexGc = functions.firestore
  .document('users/{uid}/attachments_index/{hash}')
  .onWrite(async (change, context) => {
    const uid = context.params['uid'] as string;
    const hash = context.params['hash'] as string;
    const afterExists = change.after.exists;
    let refcount = 0;
    if (afterExists) {
      const data = change.after.data() as any;
      refcount = typeof data?.refcount === 'number' ? data.refcount : 0;
    }
    if (!afterExists || refcount <= 0) {
      const path = `users/${uid}/blobs/${hash}`;
      try {
        await admin.storage().bucket().file(path).delete({ ignoreNotFound: true });
        console.log(`[GC] Deleted blob ${path}`);
      } catch (e) {
        console.error(`[GC] Failed deleting ${path}:`, e);
      }
      // If the document still exists and refcount <= 0, remove the index doc as well
      if (afterExists) {
        try {
          await change.after.ref.delete();
        } catch (e) {
          console.error(`[GC] Failed deleting index doc for ${path}:`, e);
        }
      }
    }
  });
