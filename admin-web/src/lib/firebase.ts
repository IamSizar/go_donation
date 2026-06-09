// Firebase Firestore client for the realtime events feed.
//
// This is the SAME project the old PHP admin connected to. Web API keys are
// designed to be public — security is enforced via Firestore rules on the
// project itself. If you swap projects, replace the config below or move it
// to a VITE_FIREBASE_CONFIG env var.

import { initializeApp, type FirebaseApp } from 'firebase/app'
import { getFirestore, type Firestore } from 'firebase/firestore'

const firebaseConfig = {
  apiKey: 'AIzaSyBTddZR-mvtQXFdg4XIGL4UmG5YbObIskY',
  authDomain: 'human-f1dc6.firebaseapp.com',
  projectId: 'human-f1dc6',
  storageBucket: 'human-f1dc6.firebasestorage.app',
  messagingSenderId: '463997425388',
  appId: '1:463997425388:web:0e3952c8ea97a4397ff7c9',
  measurementId: 'G-WRHHDYX9XF',
}

let _app: FirebaseApp | null = null
let _db: Firestore | null = null

export function firebaseDb(): Firestore {
  if (!_app) _app = initializeApp(firebaseConfig)
  if (!_db) _db = getFirestore(_app)
  return _db
}
