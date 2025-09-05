Firebase setup
==============

This project uses Firestore for sync ops (users/{uid}/oplog) and Firebase Storage for content-addressed blobs (users/{uid}/blobs/{hash}).

Rules
-----

- Firestore rules: `firebase/firestore.rules`
- Storage rules: `firebase/storage.rules`

Deploy steps
------------

1) Install CLI (once):
   - `npm i -g firebase-tools`
   - `firebase login`

2) Initialize project (once per repo):
   - `firebase init`
     - Choose Firestore and Storage
     - Use existing Firebase project
     - When prompted for rules paths, select:
       - Firestore rules: `firebase/firestore.rules`
       - Storage rules: `firebase/storage.rules`

3) Deploy rules:
   - `firebase deploy --only firestore:rules,storage:rules`

Notes
-----

- The app expects users to be authenticated; rules restrict access to the owner (`request.auth.uid == uid`).
- Blobs are capped at 25 MB per object; adjust in `firebase/storage.rules` if necessary.
- Oplog documents validate basic fields and restrict entity/op to the expected enums.

