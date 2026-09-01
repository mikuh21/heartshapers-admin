import { createClient } from "@supabase/supabase-js";

const url = import.meta.env.VITE_SUPABASE_URL;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

export const supabase = createClient(url, anonKey);

export const COVER_BUCKET =
  import.meta.env.VITE_BOOK_COVERS_BUCKET || "book-covers";

export const PDF_BUCKET =
  import.meta.env.VITE_BOOK_PDFS_BUCKET || "book-pdfs";