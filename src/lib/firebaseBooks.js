import {
  collection,
  doc,
  getDocs,
  query,
  where,
  orderBy,
  updateDoc,
  serverTimestamp
} from "firebase/firestore";
import { firestore } from "./firebase";

const booksRef = collection(firestore, "books");

export async function listFirebaseBooks() {
  const snapshot = await getDocs(query(
    booksRef,
    where("deleted_at", "==", null),
    orderBy("created_at", "desc")
  ));
  return snapshot.docs.map((item) => ({ id: item.id, ...item.data() }));
}

export async function softDeleteFirebaseBook(bookId) {
  if (typeof bookId !== "string" || !bookId.trim()) {
    throw new Error("A valid book ID is required.");
  }
  const bookRef = doc(firestore, "books", bookId);
  await updateDoc(bookRef, {
    deleted_at: new Date().toISOString(),
    updated_at: serverTimestamp()
  });
  // Preserve PDF and cover assets, purchases, and related history.
  return { id: bookId };
}

export async function updateFirebaseBookCover(bookId, currentCoverUrl, optimizedCoverUrl) {
  if (!bookId || !optimizedCoverUrl) throw new Error("A book ID and optimized cover URL are required.");
  const bookRef = doc(firestore, "books", bookId);
  const snapshot = await getDocs(query(booksRef, where("__name__", "==", bookId)));
  const current = snapshot.docs[0];
  if (!current || current.data().deleted_at) throw new Error("The book could not be found or has been deleted.");
  if ((current.data().cover_image_url || null) !== (currentCoverUrl || null)) {
    throw new Error("Book cover changed during optimization; the original URL was retained.");
  }
  await updateDoc(bookRef, { cover_image_url: optimizedCoverUrl, updated_at: serverTimestamp() });
  return { id: bookId };
}
