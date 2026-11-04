import {
  collection, doc, getDocs, query, where, orderBy, writeBatch, serverTimestamp
} from "firebase/firestore";
import { firestore } from "./firebase";

const pillarsRef = collection(firestore, "pillars");
const categoriesRef = collection(firestore, "categories");
const booksRef = collection(firestore, "books");

const rows = (snapshot) => snapshot.docs.map((item) => ({ id: item.id, ...item.data() }));
const active = (item) => !item.deleted_at;

async function commitChunks(operations) {
  for (let offset = 0; offset < operations.length; offset += 450) {
    const batch = writeBatch(firestore);
    operations.slice(offset, offset + 450).forEach((operation) => operation(batch));
    await batch.commit();
  }
}

export async function loadFirebaseManagedSettings() {
  const [pillarsSnapshot, categoriesSnapshot] = await Promise.all([
    getDocs(query(pillarsRef, orderBy("created_at", "asc"))),
    getDocs(query(categoriesRef, orderBy("created_at", "asc")))
  ]);
  const pillars = rows(pillarsSnapshot).filter(active);
  const categories = rows(categoriesSnapshot).filter(active);
  const byId = new Map(pillars.map((pillar) => [pillar.id, { ...pillar, name: String(pillar.name || "").trim(), categories: [] }]));
  for (const category of categories) {
    const pillar = byId.get(category.pillar_id);
    if (pillar) pillar.categories.push({ ...category, name: String(category.name || "").trim() });
  }
  return pillars.map((pillar) => {
    const entry = byId.get(pillar.id);
    return {
      id: entry.id, name: entry.name, created_at: entry.created_at,
      categories: entry.categories.map((category) => ({
        id: category.id, name: category.name, pillar_id: entry.id, is_locked: Boolean(category.is_locked)
      }))
    };
  });
}

export async function ensureFirebaseDefaultTaxonomy(defaultPillars, defaultCategories) {
  const [pillarSnapshot, categorySnapshot] = await Promise.all([getDocs(pillarsRef), getDocs(categoriesRef)]);
  const pillars = rows(pillarSnapshot);
  const categories = rows(categorySnapshot);
  const pillarByName = new Map(pillars.filter(active).map((p) => [String(p.name || "").trim().toLowerCase(), p]));
  const categoryKeys = new Set(categories.filter(active).map((c) => {
    const p = pillars.find((item) => item.id === c.pillar_id);
    return `${String(p?.name || "").trim().toLowerCase()}::${String(c.name || "").trim().toLowerCase()}`;
  }));
  const ops = [];
  for (const name of defaultPillars) {
    const key = String(name).trim().toLowerCase();
    if (!pillarByName.has(key)) {
      const id = crypto.randomUUID();
      const pillar = { id, name, created_at: new Date().toISOString(), updated_at: serverTimestamp(), deleted_at: null };
      pillarByName.set(key, pillar);
      ops.push((batch) => batch.set(doc(pillarsRef, id), pillar));
    }
  }
  for (const [pillarName, names] of Object.entries(defaultCategories)) {
    const pillar = pillarByName.get(String(pillarName).trim().toLowerCase());
    if (!pillar) continue;
    for (const name of names) {
      const key = `${String(pillarName).trim().toLowerCase()}::${String(name).trim().toLowerCase()}`;
      if (categoryKeys.has(key)) continue;
      const id = crypto.randomUUID();
      const category = { id, pillar_id: pillar.id, name, is_locked: false, created_at: new Date().toISOString(), updated_at: serverTimestamp(), deleted_at: null };
      categoryKeys.add(key);
      ops.push((batch) => batch.set(doc(categoriesRef, id), category));
    }
  }
  await commitChunks(ops);
}

export async function createFirebasePillar(name) {
  const id = crypto.randomUUID();
  await commitChunks([(batch) => batch.set(doc(pillarsRef, id), {
    name, created_at: new Date().toISOString(), updated_at: serverTimestamp(), deleted_at: null
  })]);
  return { id };
}

export async function renameFirebasePillar(pillarId, previousName, name) {
  const [pillarSnapshot, booksSnapshot] = await Promise.all([
    getDocs(query(pillarsRef, where("__name__", "==", pillarId))),
    getDocs(query(booksRef, where("pillar", "==", previousName)))
  ]);
  if (pillarSnapshot.empty || !active(pillarSnapshot.docs[0].data())) throw new Error("Pillar not found or already deleted.");
  const ops = [(batch) => batch.update(doc(pillarsRef, pillarId), { name, updated_at: serverTimestamp() })];
  booksSnapshot.docs.forEach((book) => ops.push((batch) => batch.update(book.ref, { pillar: name, updated_at: serverTimestamp() })));
  await commitChunks(ops);
}

export async function createFirebaseCategory(pillarId, name) {
  const id = crypto.randomUUID();
  await commitChunks([(batch) => batch.set(doc(categoriesRef, id), {
    id, pillar_id: pillarId, name, is_locked: false, created_at: new Date().toISOString(), updated_at: serverTimestamp(), deleted_at: null
  })]);
  return { id };
}

export async function renameFirebaseCategory(categoryId, pillarName, previousName, name) {
  const [categorySnapshot, booksSnapshot] = await Promise.all([
    getDocs(query(categoriesRef, where("__name__", "==", categoryId))),
    getDocs(query(booksRef, where("pillar", "==", pillarName), where("subcategory", "==", previousName)))
  ]);
  if (categorySnapshot.empty || !active(categorySnapshot.docs[0].data())) throw new Error("Category not found or already deleted.");
  const ops = [(batch) => batch.update(doc(categoriesRef, categoryId), { name, updated_at: serverTimestamp() })];
  booksSnapshot.docs.forEach((book) => ops.push((batch) => batch.update(book.ref, { subcategory: name, updated_at: serverTimestamp() })));
  await commitChunks(ops);
}

export async function setFirebaseCategoryLock(categoryId, isLocked) {
  await commitChunks([(batch) => batch.update(doc(categoriesRef, categoryId), { is_locked: isLocked, updated_at: serverTimestamp() })]);
}

export async function softDeleteFirebaseTaxonomy(targetType, targetId) {
  const [pillarSnapshot, categorySnapshot, booksSnapshot] = await Promise.all([
    targetType === "pillar" ? getDocs(query(pillarsRef, where("__name__", "==", targetId))) : Promise.resolve(null),
    targetType === "category" ? getDocs(query(categoriesRef, where("__name__", "==", targetId))) : Promise.resolve(null),
    getDocs(booksRef)
  ]);
  const pillar = pillarSnapshot?.docs[0]?.data();
  const category = categorySnapshot?.docs[0]?.data();
  const target = pillar || category;
  if (!target || !active(target)) throw new Error("The selected record could not be found or is already deleted.");
  const timestamp = new Date().toISOString();
  const ops = [];
  if (targetType === "pillar") {
    const categories = rows(await getDocs(query(categoriesRef, where("pillar_id", "==", targetId)))).filter(active);
    const categoryIds = new Set(categories.map((item) => item.id));
    ops.push((batch) => batch.update(doc(pillarsRef, targetId), { deleted_at: timestamp, updated_at: serverTimestamp() }));
    categories.forEach((item) => ops.push((batch) => batch.update(doc(categoriesRef, item.id), { deleted_at: timestamp, updated_at: serverTimestamp() })));
    booksSnapshot.docs.filter((book) => book.data().pillar === target.name).forEach((book) => ops.push((batch) => batch.update(book.ref, { deleted_at: timestamp, updated_at: serverTimestamp() })));
  } else {
    ops.push((batch) => batch.update(doc(categoriesRef, targetId), { deleted_at: timestamp, updated_at: serverTimestamp() }));
    booksSnapshot.docs.filter((book) => book.data().pillar === (target.pillar_name || "") && book.data().subcategory === target.name).forEach((book) => ops.push((batch) => batch.update(book.ref, { deleted_at: timestamp, updated_at: serverTimestamp() })));
  }
  await commitChunks(ops);
  return true;
}
