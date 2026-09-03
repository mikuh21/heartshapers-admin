import React, { createContext, useContext, useEffect, useMemo, useRef, useState } from "react";
import {
  BookOpen,
  LayoutDashboard,
  LogOut,
  Menu,
  Plus,
  Search,
  Settings,
  X,
  Pencil,
  Trash2,
  Lock,
  Unlock,
  Upload,
  FileText,
  Image as ImageIcon,
  ChevronDown,
  Loader2,
  Users,
  ShieldCheck,
  Eye,
  EyeOff,
  AlertTriangle
} from "lucide-react";
import { supabase, COVER_BUCKET, PDF_BUCKET } from "./lib/supabase";
import {
  getAuthRole,
  isAdminUser,
  isAdminWebUser,
  isSuperAdmin,
  listAdmins,
  listUsers,
  createAdmin,
  updateAdminStatus,
  updateUserStatus
} from "./lib/adminUsers";

const DEFAULT_BOOK_AUTHOR = "Compiled and Edited by HEARTSHAPERS";

const EMPTY_BOOK = {
  id: null,
  title: "",
  author: DEFAULT_BOOK_AUTHOR,
  cover_image_url: "",
  pdf_url: "",
  pillar: "",
  subcategory: "",
  description: "",
  keywords: "",
  is_locked: false
};

const PILLAR_OPTIONS = ["Family", "Work", "Ministry"];
const SUBCATEGORY_OPTIONS = ["Devotionals", "Discipleship", "Leadership", "Heroes of Faith", "Group Activities"];
const ToastContext = createContext(null);

function normalizeFilterValue(value) {
  return String(value || "").trim().toLowerCase();
}

function ToastProvider({ children }) {
  const [toasts, setToasts] = useState([]);

  function removeToast(id) {
    setToasts((current) => current.filter((toast) => toast.id !== id));
  }

  function showToast(message, type = "success") {
    const id = `${Date.now()}-${Math.random()}`;
    setToasts((current) => [...current, { id, message, type }]);
  }

  return (
    <ToastContext.Provider value={{ showToast }}>
      {children}
      <div className="toast-region" aria-live="polite" aria-atomic="true">
        {toasts.map((toast) => (
          <Toast key={toast.id} {...toast} onClose={() => removeToast(toast.id)} />
        ))}
      </div>
    </ToastContext.Provider>
  );
}

function useToast() {
  const context = useContext(ToastContext);
  if (!context) throw new Error("useToast must be used within ToastProvider");
  return context;
}

function Toast({ message, type, onClose }) {
  useEffect(() => {
    const timer = window.setTimeout(onClose, 7000);
    return () => window.clearTimeout(timer);
  }, []);

  return (
    <div className={`toast toast-${type}`} role={type === "error" ? "alert" : "status"}>
      <span className="toast-indicator" aria-hidden="true" />
      <span>{message}</span>
      <button type="button" className="toast-close" onClick={onClose} aria-label="Dismiss notification">
        <X size={16} />
      </button>
    </div>
  );
}

function ConfirmModal({ title, message, secondaryMessage, actionLabel, busyLabel, tone = "danger", icon: Icon = AlertTriangle, onClose, onConfirm }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const dialogRef = useRef(null);

  useEffect(() => {
    const scrollY = window.scrollY;
    const bodyStyle = document.body.style;
    const originalBodyStyles = {
      overflow: bodyStyle.overflow,
      paddingRight: bodyStyle.paddingRight,
      position: bodyStyle.position,
      top: bodyStyle.top,
      width: bodyStyle.width
    };
    const scrollbarWidth = window.innerWidth - document.documentElement.clientWidth;

    bodyStyle.overflow = "hidden";
    bodyStyle.position = "fixed";
    bodyStyle.top = `-${scrollY}px`;
    bodyStyle.width = "100%";
    if (scrollbarWidth > 0) bodyStyle.paddingRight = `${scrollbarWidth}px`;

    return () => {
      bodyStyle.overflow = originalBodyStyles.overflow;
      bodyStyle.paddingRight = originalBodyStyles.paddingRight;
      bodyStyle.position = originalBodyStyles.position;
      bodyStyle.top = originalBodyStyles.top;
      bodyStyle.width = originalBodyStyles.width;
      window.scrollTo(0, scrollY);
    };
  }, []);

  useEffect(() => {
    const previousActiveElement = document.activeElement;
    dialogRef.current?.focus();

    function handleKeyDown(event) {
      if (event.key === "Escape" && !busy) onClose();
    }

    document.addEventListener("keydown", handleKeyDown);
    return () => {
      document.removeEventListener("keydown", handleKeyDown);
      previousActiveElement?.focus?.();
    };
  }, [busy, onClose]);

  async function handleConfirm() {
    setBusy(true);
    setError("");
    try {
      const completed = await onConfirm();
      if (completed !== false) onClose();
    } catch (err) {
      setError(err.message || "Unable to complete this action. Please try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="confirm-backdrop">
      <div
        className="confirm-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="confirm-modal-title"
        tabIndex={-1}
        ref={dialogRef}
      >
        <div className={`confirm-icon confirm-icon-${tone}`} aria-hidden="true"><Icon size={24} /></div>
        <h3 id="confirm-modal-title">{title}</h3>
        <p>{message}</p>
        {secondaryMessage && <span>{secondaryMessage}</span>}
        {error && <div className="error-box confirm-error">{error}</div>}
        <div className="modal-footer confirm-footer">
          <button type="button" className="secondary-btn" onClick={onClose} disabled={busy}>Cancel</button>
          <button type="button" className={`${tone}-btn`} onClick={handleConfirm} disabled={busy}>
            {busy ? busyLabel || `${actionLabel}...` : actionLabel}
          </button>
        </div>
      </div>
    </div>
  );
}

function App() {
  const [session, setSession] = useState(null);
  const [loadingAuth, setLoadingAuth] = useState(true);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      setLoadingAuth(false);
    });

    const { data: listener } = supabase.auth.onAuthStateChange((_event, next) => {
      setSession(next);
    });

    return () => listener.subscription.unsubscribe();
  }, []);

  if (loadingAuth) return <LoadingScreen />;
  if (!session) return <Login />;
  if (!isAdminWebUser(session.user)) return <AdminAccessDenied />;

  return (
    <ToastProvider>
      <AdminApp session={session} />
    </ToastProvider>
  );
}

function Login() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function handleLogin(e) {
    e.preventDefault();
    setBusy(true);
    setError("");

    const { data, error } = await supabase.auth.signInWithPassword({
      email: email.trim(),
      password
    });

    if (error) {
      setError(error.message);
      setBusy(false);
      return;
    }

    const role = getAuthRole(data.user);
    if (!isAdminWebUser(data.user)) {
      await supabase.auth.signOut();
      setError("This account does not have permission to access Heartshapers Admin.");
      setBusy(false);
      return;
    }

    setBusy(false);
  }

  return (
    <div className="login-page">
      <div className="login-card">
        <div className="brand-mark">H</div>
        <h1>Heartshapers</h1>
        <p className="muted">Admin Management</p>

        <form onSubmit={handleLogin} className="login-form">
          <label>Email</label>
          <input
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="admin@example.com"
            required
          />

          <label>Password</label>
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="Enter password"
            required
          />

          {error && <div className="error-box">{error}</div>}

          <button className="primary-btn full" disabled={busy}>
            {busy ? <Loader2 size={18} className="spin" /> : "Log in"}
          </button>
        </form>
      </div>
    </div>
  );
}

function AdminAccessDenied() {
  return (
    <div className="login-page">
      <div className="login-card">
        <div className="brand-mark">H</div>
        <h1>Access denied</h1>
        <p className="muted">This account does not have permission to access Heartshapers Admin.</p>
        <button
          className="primary-btn full"
          onClick={async () => {
            await supabase.auth.signOut();
            window.location.reload();
          }}
        >
          Return to login
        </button>
      </div>
    </div>
  );
}

function AdminApp({ session }) {
  const [page, setPage] = useState("dashboard");
  const [mobileOpen, setMobileOpen] = useState(false);
  const [logoutConfirmationOpen, setLogoutConfirmationOpen] = useState(false);
  const canManageUsers = isAdminUser(session.user);
  const canManageAdmins = isSuperAdmin(session.user);

  async function logout() {
    return supabase.auth.signOut();
  }

  return (
    <div className="app-shell">
      <aside className={`sidebar ${mobileOpen ? "open" : ""}`}>
        <div className="sidebar-brand">
          <img
            className="sidebar-brand-logo"
            src="/FINAL%20HEARTSHAPERS%20ICON.svg"
            alt="Heartshapers"
          />
          <div>
            <strong>Heartshapers</strong>
            <span>Admin</span>
          </div>
          <button className="icon-btn mobile-close" onClick={() => setMobileOpen(false)}>
            <X size={20} />
          </button>
        </div>

        <nav>
          <NavItem
            icon={<LayoutDashboard size={19} />}
            label="Dashboard"
            active={page === "dashboard"}
            onClick={() => {
              setPage("dashboard");
              setMobileOpen(false);
            }}
          />
          <NavItem
            icon={<BookOpen size={19} />}
            label="Books"
            active={page === "books"}
            onClick={() => {
              setPage("books");
              setMobileOpen(false);
            }}
          />
          <NavItem
            icon={<Users size={19} />}
            label="Users"
            active={page === "users"}
            onClick={() => {
              setPage("users");
              setMobileOpen(false);
            }}
          />
          {canManageAdmins && (
            <NavItem
              icon={<ShieldCheck size={19} />}
              label="Admins"
              active={page === "admins"}
              onClick={() => {
                setPage("admins");
                setMobileOpen(false);
              }}
            />
          )}
        </nav>

        <div className="sidebar-bottom">
          <NavItem
            icon={<Settings size={19} />}
            label="Settings"
            active={page === "settings"}
            onClick={() => {
              setPage("settings");
              setMobileOpen(false);
            }}
          />
          <button className="nav-item logout-item" onClick={() => setLogoutConfirmationOpen(true)}>
            <LogOut size={19} />
            <span>Logout</span>
          </button>
        </div>
      </aside>

      {mobileOpen && <div className="overlay" onClick={() => setMobileOpen(false)} />}

      <main className="main">
        <header className="topbar">
          <button className="icon-btn mobile-menu" onClick={() => setMobileOpen(true)}>
            <Menu size={22} />
          </button>
          <div className="account">
            <div className="avatar">{(session.user.email || "A")[0].toUpperCase()}</div>
            <span>{session.user.email}</span>
          </div>
        </header>

        <div className="content">
          {page === "dashboard" && <Dashboard goBooks={() => setPage("books")} />}
          {page === "books" && <Books />}
          {page === "users" && <UsersPage canManageUsers={canManageUsers} />}
          {page === "admins" && (canManageAdmins ? <AdminsPage /> : <AccessDeniedPage message="You do not have permission to manage administrator accounts." />)}
          {page === "settings" && <SettingsPage />}
        </div>
      </main>
      {logoutConfirmationOpen && (
        <ConfirmModal
          title="Log Out?"
          message="Are you sure you want to log out?"
          actionLabel="Log Out"
          busyLabel="Logging out..."
          tone="danger"
          icon={LogOut}
          onClose={() => setLogoutConfirmationOpen(false)}
          onConfirm={async () => {
            const result = await logout();
            if (result?.error) throw result.error;
            return true;
          }}
        />
      )}
    </div>
  );
}

function NavItem({ icon, label, active, onClick }) {
  return (
    <button className={`nav-item ${active ? "active" : ""}`} onClick={onClick}>
      {icon}
      <span>{label}</span>
    </button>
  );
}

function Dashboard({ goBooks }) {
  const [stats, setStats] = useState({
    total: 0,
    locked: 0,
    free: 0,
    pillars: 0
  });
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadStats();
  }, []);

  async function loadStats() {
    setLoading(true);
    const { data, error } = await supabase
      .from("books")
      .select("id, pillar, is_locked");

    if (!error) {
      const rows = data || [];
      setStats({
        total: rows.length,
        locked: rows.filter((b) => b.is_locked).length,
        free: rows.filter((b) => !b.is_locked).length,
        pillars: new Set(rows.map((b) => b.pillar).filter(Boolean)).size
      });
    }
    setLoading(false);
  }

  return (
    <>
      <div className="welcome-row">
        <div>
          <h3>Overview</h3>
          <p className="muted">A simple overview of your Heartshapers books.</p>
        </div>
        <button className="primary-btn" onClick={goBooks}>
          <BookOpen size={18} /> Manage Books
        </button>
      </div>

      <div className="stats-grid">
        <StatCard label="Total Books" value={stats.total} icon={<BookOpen size={21} />} loading={loading} />
        <StatCard label="Locked Books" value={stats.locked} icon={<Lock size={21} />} loading={loading} />
        <StatCard label="Free Books" value={stats.free} icon={<Unlock size={21} />} loading={loading} />
        <StatCard label="Pillars Used" value={stats.pillars} icon={<LayoutDashboard size={21} />} loading={loading} />
      </div>

      <div className="info-card">
        <div className="info-icon"><BookOpen size={22} /></div>
        <div>
          <h4>Book management</h4>
          <p>Add, edit, upload, and remove books from one simple page.</p>
        </div>
      </div>
    </>
  );
}

function StatCard({ label, value, icon, loading }) {
  return (
    <div className="stat-card">
      <div className="stat-icon">{icon}</div>
      <div>
        <span>{label}</span>
        <strong>{loading ? "—" : value}</strong>
      </div>
    </div>
  );
}

function Books() {
  const { showToast } = useToast();
  const [books, setBooks] = useState([]);
  const [search, setSearch] = useState("");
  const [pillar, setPillar] = useState("All Pillars");
  const [subcategory, setSubcategory] = useState("All Subcategories");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [modal, setModal] = useState(null);
  const [selected, setSelected] = useState(null);
  const [bookToDelete, setBookToDelete] = useState(null);

  async function loadBooks() {
    setLoading(true);
    setError("");

    const { data, error } = await supabase
      .from("books")
      .select("id,title,author,cover_image_url,pdf_url,pillar,subcategory,description,keywords,created_at,is_locked")
      .order("created_at", { ascending: false });

    if (error) setError(error.message);
    else setBooks(data || []);
    setLoading(false);
  }

  useEffect(() => {
    loadBooks();
  }, []);

  const availableSubcategories = pillar === "All Pillars" ? [] : SUBCATEGORY_OPTIONS;

  const filtered = books.filter((book) => {
    const text = `${book.title || ""} ${book.subcategory || ""} ${book.pillar || ""}`.toLowerCase();
    const matchesPillar = pillar === "All Pillars" || normalizeFilterValue(book.pillar) === normalizeFilterValue(pillar);
    const matchesSubcategory = subcategory === "All Subcategories" || normalizeFilterValue(book.subcategory) === normalizeFilterValue(subcategory);
    return text.includes(search.toLowerCase()) && matchesPillar && matchesSubcategory;
  });

  async function deleteBook(book) {
    const { error } = await supabase.from("books").delete().eq("id", book.id);
    if (error) {
      setError(error.message);
      return false;
    }

    setBooks((current) => current.filter((item) => item.id !== book.id));
    showToast("Book deleted successfully.", "error");
    return true;
  }

  return (
    <>
      <div className="page-heading">
        <div>
          <h3>Books</h3>
          <p className="muted">Manage the books stored in Heartshapers.</p>
        </div>
        <button className="primary-btn" onClick={() => { setSelected(null); setModal("book"); }}>
          <Plus size={18} /> Add Book
        </button>
      </div>

      <div className="toolbar">
        <div className="search-box">
          <Search size={18} />
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search books..."
          />
        </div>

        <div className="select-box">
          <select
            value={pillar}
            onChange={(e) => {
              setPillar(e.target.value);
              setSubcategory("All Subcategories");
            }}
          >
            <option>All Pillars</option>
            {PILLAR_OPTIONS.map((item) => <option key={item}>{item}</option>)}
          </select>
          <ChevronDown size={16} />
        </div>

        {pillar !== "All Pillars" && (
          <div className="select-box">
            <select value={subcategory} onChange={(e) => setSubcategory(e.target.value)}>
              <option>All Subcategories</option>
              {availableSubcategories.map((item) => <option key={item}>{item}</option>)}
            </select>
            <ChevronDown size={16} />
          </div>
        )}
      </div>

      {error && <div className="error-box page-error">{error}</div>}

      <div className="table-card">
        {loading ? (
          <div className="empty-state"><Loader2 className="spin" /> Loading books...</div>
        ) : filtered.length === 0 ? (
          <div className="empty-state">
            <BookOpen size={34} />
            <strong>No books found</strong>
            <span>
              {pillar !== "All Pillars" && subcategory !== "All Subcategories"
                ? "No books found for this Pillar and Subcategory."
                : "Add a book or change your search."}
            </span>
          </div>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Book</th>
                  <th>Pillar</th>
                  <th>Subcategory</th>
                  <th>Access</th>
                  <th>Created</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((book) => (
                  <tr key={book.id}>
                    <td>
                      <div className="book-cell">
                        {book.cover_image_url ? (
                          <img src={book.cover_image_url} alt="" />
                        ) : (
                          <div className="cover-placeholder"><BookOpen size={20} /></div>
                        )}
                        <strong>{book.title || "Untitled"}</strong>
                      </div>
                    </td>
                    <td>{book.pillar || "—"}</td>
                    <td>{book.subcategory || "—"}</td>
                    <td>
                      <span className={`status ${book.is_locked ? "locked" : "free"}`}>
                        {book.is_locked ? <Lock size={13} /> : <Unlock size={13} />}
                        {book.is_locked ? "Locked" : "Free"}
                      </span>
                    </td>
                    <td>{formatDate(book.created_at)}</td>
                    <td>
                      <div className="actions">
                        <button className="icon-btn" title="Edit" onClick={() => { setSelected(book); setModal("book"); }}>
                          <Pencil size={17} />
                        </button>
                        <button className="icon-btn danger" title="Delete" onClick={() => setBookToDelete(book)}>
                          <Trash2 size={17} />
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {modal === "book" && (
        <BookModal
          book={selected}
          onClose={() => setModal(null)}
          onSaved={async (message) => {
            setModal(null);
            await loadBooks();
            showToast(message, "success");
          }}
        />
      )}
      {bookToDelete && (
        <ConfirmModal
          title="Delete Book?"
          message={`Are you sure you want to delete "${bookToDelete.title || "Untitled"}"?`}
          secondaryMessage="This action cannot be undone."
          actionLabel="Delete"
          onClose={() => setBookToDelete(null)}
          onConfirm={() => deleteBook(bookToDelete)}
        />
      )}
    </>
  );
}

function BookModal({ book, onClose, onSaved }) {
  const [form, setForm] = useState(() => {
    if (!book) return { ...EMPTY_BOOK };

    return {
      ...EMPTY_BOOK,
      ...book,
      author: typeof book.author === "string" && book.author.trim() ? book.author : DEFAULT_BOOK_AUTHOR,
      description: typeof book.description === "string" ? book.description : "",
      keywords: Array.isArray(book.keywords)
        ? book.keywords.join(", ")
        : typeof book.keywords === "string"
          ? book.keywords
          : ""
    };
  });
  const [coverFile, setCoverFile] = useState(null);
  const [pdfFile, setPdfFile] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [fieldErrors, setFieldErrors] = useState({});
  const isAdd = !form.id;

  useEffect(() => {
    const scrollY = window.scrollY;
    const bodyStyle = document.body.style;
    const originalBodyStyles = {
      overflow: bodyStyle.overflow,
      paddingRight: bodyStyle.paddingRight,
      position: bodyStyle.position,
      top: bodyStyle.top,
      width: bodyStyle.width
    };
    const scrollbarWidth = window.innerWidth - document.documentElement.clientWidth;

    bodyStyle.overflow = "hidden";
    bodyStyle.position = "fixed";
    bodyStyle.top = `-${scrollY}px`;
    bodyStyle.width = "100%";
    if (scrollbarWidth > 0) bodyStyle.paddingRight = `${scrollbarWidth}px`;

    return () => {
      bodyStyle.overflow = originalBodyStyles.overflow;
      bodyStyle.paddingRight = originalBodyStyles.paddingRight;
      bodyStyle.position = originalBodyStyles.position;
      bodyStyle.top = originalBodyStyles.top;
      bodyStyle.width = originalBodyStyles.width;
      window.scrollTo(0, scrollY);
    };
  }, []);

  function update(field, value) {
    setForm((current) => ({ ...current, [field]: value }));
    setFieldErrors((current) => {
      if (!current[field]) return current;
      const next = { ...current };
      delete next[field];
      return next;
    });
  }

  function normalizeDescription(value) {
    const trimmed = String(value || "").trim();
    return trimmed.length > 0 ? trimmed : null;
  }

  function normalizeKeywords(value) {
    const raw = typeof value === "string" ? value : "";
    const cleaned = raw
      .split(",")
      .map((item) => item.trim())
      .filter(Boolean);

    const unique = [];
    const seen = new Set();

    for (const item of cleaned) {
      const key = item.toLowerCase();
      if (!seen.has(key)) {
        seen.add(key);
        unique.push(item);
      }
    }

    return unique;
  }

  async function uploadFile(file, bucket, folder) {
    if (!file) return null;

    const safeName = file.name.toLowerCase().replace(/[^a-z0-9._-]/g, "-");
    const path = `${folder}/${crypto.randomUUID()}-${safeName}`;

    const { error } = await supabase.storage.from(bucket).upload(path, file, {
      upsert: false
    });

    if (error) throw error;

    const { data } = supabase.storage.from(bucket).getPublicUrl(path);
    return data.publicUrl;
  }

  async function saveBook(e) {
    e.preventDefault();
    setError("");

    const errors = {};
    const title = typeof form.title === "string" ? form.title.trim() : "";
    const author = typeof form.author === "string" ? form.author.trim() : "";
    const description = typeof form.description === "string" ? form.description.trim() : "";
    const keywords = normalizeKeywords(form.keywords);

    if (!title) errors.title = "Title is required.";
    if (!author) errors.author = "Author is required.";
    if (!PILLAR_OPTIONS.includes(form.pillar)) errors.pillar = "Please select a pillar.";
    if (!SUBCATEGORY_OPTIONS.includes(form.subcategory)) errors.subcategory = "Please select a subcategory.";
    if (isAdd && !coverFile) errors.cover = "Cover image is required.";
    if (isAdd && !pdfFile) errors.pdf = "PDF is required.";
    if (isAdd && coverFile && !coverFile.type.startsWith("image/")) errors.cover = "Please select a valid cover image.";
    if (isAdd && pdfFile && pdfFile.type !== "application/pdf" && !pdfFile.name.toLowerCase().endsWith(".pdf")) {
      errors.pdf = "Please select a valid PDF file.";
    }
    if (isAdd && !description) errors.description = "Description is required.";
    if (isAdd && keywords.length === 0) errors.keywords = "At least one keyword is required.";

    setFieldErrors(errors);
    if (Object.keys(errors).length > 0) {
      return;
    }

    setBusy(true);

    try {
      let coverUrl = form.cover_image_url || null;
      let pdfUrl = form.pdf_url || null;

      if (coverFile) {
        coverUrl = await uploadFile(coverFile, COVER_BUCKET, "covers");
      }

      if (pdfFile) {
        pdfUrl = await uploadFile(pdfFile, PDF_BUCKET, "pdfs");
      }

      const payload = {
        title: form.title.trim(),
        author,
        cover_image_url: coverUrl,
        pdf_url: pdfUrl,
        pillar: form.pillar.trim(),
        subcategory: form.subcategory.trim() || null,
        description: normalizeDescription(form.description),
        keywords: normalizeKeywords(form.keywords),
        is_locked: Boolean(form.is_locked)
      };

      let result;

      if (form.id) {
        const { data: updatedBook, error } = await supabase
          .from("books")
          .update(payload)
          .eq("id", form.id)
          .select("id")
          .maybeSingle();

        if (error) {
          console.error("Book update failed", {
            bookId: form.id,
            message: error.message,
            code: error.code,
            details: error.details,
            hint: error.hint
          });

          throw error;
        }

        if (!updatedBook) {
          console.error("Book update affected no rows", {
            bookId: form.id
          });

          throw new Error(
            "The book could not be updated. Please check administrator permissions."
          );
        }

        await onSaved("Book updated successfully.");
        return;
      }

      result = await supabase
        .from("books")
        .insert(payload)
        .select()
        .single();

      if (result?.error) {
        console.error("Book create failed", {
          message: result.error.message,
          code: result.error.code,
          details: result.error.details,
          hint: result.error.hint
        });
        throw result.error;
      }

      await onSaved("Book added successfully.");
    } catch (err) {
      console.error("Book save error:", err);
      setError(err.message || "Unable to update the book. Please try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="modal-backdrop">
      <div className="modal">
        <div className="modal-header">
          <div>
            <h3>{form.id ? "Edit Book" : "Add Book"}</h3>
          </div>
          <button className="icon-btn" onClick={onClose}><X size={20} /></button>
        </div>

        <form onSubmit={saveBook}>
          <div className="modal-body">
            {error && <div className="error-box">{error}</div>}

            <label>Book Title *</label>
            <input value={form.title} onChange={(e) => update("title", e.target.value)} placeholder="Enter book title" aria-invalid={Boolean(fieldErrors.title)} />
            {fieldErrors.title && <div className="field-error">{fieldErrors.title}</div>}

            <label>Author *</label>
            <input value={form.author} onChange={(e) => update("author", e.target.value)} placeholder="Enter book author" aria-invalid={Boolean(fieldErrors.author)} />
            {fieldErrors.author && <div className="field-error">{fieldErrors.author}</div>}

            <label>Pillar *</label>
            <select value={form.pillar} onChange={(e) => update("pillar", e.target.value)} aria-invalid={Boolean(fieldErrors.pillar)}>
              <option value="">Select Pillar</option>
              {PILLAR_OPTIONS.map((option) => <option key={option} value={option}>{option}</option>)}
            </select>
            {fieldErrors.pillar && <div className="field-error">{fieldErrors.pillar}</div>}

            <label>Subcategory *</label>
            <select value={form.subcategory || ""} onChange={(e) => update("subcategory", e.target.value)} aria-invalid={Boolean(fieldErrors.subcategory)}>
              <option value="">Select Subcategory</option>
              {SUBCATEGORY_OPTIONS.map((option) => <option key={option} value={option}>{option}</option>)}
            </select>
            {fieldErrors.subcategory && <div className="field-error">{fieldErrors.subcategory}</div>}

            <label>Description {isAdd ? "*" : ""}</label>
            <textarea
              value={form.description || ""}
              onChange={(e) => update("description", e.target.value)}
              placeholder="Enter a description for this book"
              rows={4}
              aria-invalid={Boolean(fieldErrors.description)}
            />
            {fieldErrors.description && <div className="field-error">{fieldErrors.description}</div>}

            <label>Keywords {isAdd ? "*" : ""}</label>
            <input
              value={form.keywords || ""}
              onChange={(e) => update("keywords", e.target.value)}
              placeholder="Evangelism, Gospel, Compassion"
              aria-invalid={Boolean(fieldErrors.keywords)}
            />
            <div className="field-hint">Separate keywords with commas.</div>
            {fieldErrors.keywords && <div className="field-error">{fieldErrors.keywords}</div>}

            <div className="file-grid">
              <FileInput
                label="Cover Image"
                accept="image/*"
                file={coverFile}
                current={form.cover_image_url}
                icon={<ImageIcon size={19} />}
                onChange={setCoverFile}
                error={fieldErrors.cover}
                required={isAdd}
              />
              <FileInput
                label="Book PDF"
                accept="application/pdf,.pdf"
                file={pdfFile}
                current={form.pdf_url}
                icon={<FileText size={19} />}
                onChange={setPdfFile}
                error={fieldErrors.pdf}
                required={isAdd}
              />
            </div>

            <div className="access-box">
              <div>
                <strong>Book access</strong>
                <span className="muted">Locked books can be treated as restricted by your app.</span>
              </div>
              <label className="switch-row">
                <input
                  type="checkbox"
                  checked={Boolean(form.is_locked)}
                  onChange={(e) => update("is_locked", e.target.checked)}
                />
                <span>{form.is_locked ? "Locked" : "Free"}</span>
              </label>
            </div>
          </div>

          <div className="modal-footer">
            <button type="button" className="secondary-btn" onClick={onClose}>Cancel</button>
            <button className="primary-btn" disabled={busy}>
              {busy ? <><Loader2 size={18} className="spin" /> Saving...</> : <><Upload size={18} /> {form.id ? "Save Changes" : "Add Book"}</>}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

function FileInput({ label, accept, file, current, icon, onChange, error, required }) {
  return (
    <div>
      <label>{label}{required ? " *" : ""}</label>
      <label className="file-input">
        <input type="file" accept={accept} onChange={(e) => onChange(e.target.files?.[0] || null)} />
        {icon}
        <span>{file ? file.name : current ? "File already uploaded" : "Choose file"}</span>
      </label>
      {error && <div className="field-error">{error}</div>}
    </div>
  );
}

function UsersPage({ canManageUsers }) {
  const { showToast } = useToast();

  if (!canManageUsers) {
    return (
      <div className="settings-card access-card">
        <h3>Access denied</h3>
        <p className="muted">You do not have permission to manage user accounts in Heartshapers Admin.</p>
      </div>
    );
  }

  const [users, setUsers] = useState([]);
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [actionLoadingId, setActionLoadingId] = useState(null);
  const [selectedUser, setSelectedUser] = useState(null);
  const [userToToggle, setUserToToggle] = useState(null);

  async function loadUsers() {
    setLoading(true);
    setError("");

    try {
      const nextUsers = await listUsers();
      setUsers(nextUsers);
    } catch (err) {
      setUsers([]);
      setError(err.message || "Unable to load user accounts.");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    loadUsers();
  }, []);

  const filteredUsers = useMemo(() => {
    const query = search.trim().toLowerCase();
    if (!query) return users;

    return users.filter((user) => {
      const searchText = `${user.full_name || ""} ${user.email || ""}`.toLowerCase();
      return searchText.includes(query);
    });
  }, [users, search]);

  async function handleStatusToggle(user) {
    setActionLoadingId(user.id);
    try {
      const updatedUser = await updateUserStatus(user.id, !user.disabled);
      if (updatedUser) {
        setUsers((current) => current.map((item) => item.id === updatedUser.id ? updatedUser : item));
        setSelectedUser((currentUser) => (currentUser && currentUser.id === updatedUser.id ? updatedUser : currentUser));
        showToast(`User ${updatedUser.disabled ? "disabled" : "enabled"} successfully.`, updatedUser.disabled ? "error" : "success");
        return true;
      }
      return false;
    } catch (err) {
      setError(err.message || "Unable to update this user account right now.");
      return false;
    } finally {
      setActionLoadingId(null);
    }
  }

  return (
    <>
      <div className="page-heading">
        <div>
          <h3>Users</h3>
          <p className="muted">Manage Heartshapers user accounts.</p>
        </div>
      </div>

      <div className="toolbar">
        <div className="search-box user-search-box">
          <Search size={18} />
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search users by name or email..."
          />
        </div>
      </div>

      {error && <div className="error-box page-error">{error}</div>}

      <div className="table-card">
        {loading ? (
          <div className="empty-state"><Loader2 className="spin" /> Loading users...</div>
        ) : users.length === 0 ? (
          <div className="empty-state">
            <Users size={34} />
            <strong>No users found</strong>
            <span>There are currently no user accounts available.</span>
          </div>
        ) : filteredUsers.length === 0 ? (
          <div className="empty-state">
            <Search size={34} />
            <strong>No matching users</strong>
            <span>Try a different name or email address.</span>
          </div>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>User</th>
                  <th>Email</th>
                  <th>Account Status</th>
                  <th>Email Verification</th>
                  <th>Date Joined</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {filteredUsers.map((user) => (
                  <tr key={user.id}>
                    <td>
                      <div className="user-cell">
                        <div className="user-avatar">{getInitials(user.full_name || user.email)}</div>
                        <div className="user-meta">
                          <strong>{user.full_name || "Unnamed user"}</strong>
                        </div>
                      </div>
                    </td>
                    <td>{user.email || "—"}</td>
                    <td>
                      <span className={`status ${user.disabled ? "disabled" : "active"}`}>
                        {user.disabled ? <Lock size={13} /> : <Unlock size={13} />}
                        {user.disabled ? "Disabled" : "Active"}
                      </span>
                    </td>
                    <td>
                      <span className={`status ${user.email_verified ? "verified" : "unverified"}`}>
                        {user.email_verified ? "Verified" : "Unverified"}
                      </span>
                    </td>
                    <td>{formatDate(user.created_at)}</td>
                    <td>
                      <div className="user-actions">
                        <button className="secondary-btn small" onClick={() => setSelectedUser(user)}>
                          View User
                        </button>
                        <button
                          className="secondary-btn small danger"
                          onClick={() => setUserToToggle(user)}
                          disabled={actionLoadingId === user.id}
                        >
                          {actionLoadingId === user.id ? <Loader2 size={16} className="spin" /> : user.disabled ? "Enable" : "Disable"}
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {selectedUser && (
        <UserDetailsModal
          user={selectedUser}
          onClose={() => setSelectedUser(null)}
          onToggleStatus={() => setUserToToggle(selectedUser)}
          toggling={actionLoadingId === selectedUser.id}
        />
      )}
      {userToToggle && (
        <ConfirmModal
          title={`${userToToggle.disabled ? "Enable" : "Disable"} User?`}
          message={`Are you sure you want to ${userToToggle.disabled ? "enable" : "disable"} "${userToToggle.full_name || userToToggle.email || "this user"}"?`}
          secondaryMessage={userToToggle.disabled ? "The user will regain access to the application." : "The user will no longer be able to access the application."}
          actionLabel={userToToggle.disabled ? "Enable" : "Disable"}
          tone={userToToggle.disabled ? "success" : "danger"}
          onClose={() => setUserToToggle(null)}
          onConfirm={() => handleStatusToggle(userToToggle)}
        />
      )}
    </>
  );
}

function UserDetailsModal({ user, onClose, onToggleStatus, toggling }) {
  return (
    <div className="modal-backdrop">
      <div className="modal user-modal">
        <div className="modal-header">
          <div>
            <h3>User Details</h3>
            <p className="muted">Review account information and status.</p>
          </div>
          <button className="icon-btn" onClick={onClose}><X size={20} /></button>
        </div>

        <div className="modal-body">
          <div className="detail-row">
            <div className="detail-label">Full Name</div>
            <div className="detail-value">{user.full_name || "Unnamed user"}</div>
          </div>
          <div className="detail-row">
            <div className="detail-label">Email</div>
            <div className="detail-value">{user.email || "—"}</div>
          </div>
          <div className="detail-row">
            <div className="detail-label">Date Joined</div>
            <div className="detail-value">{formatDate(user.created_at)}</div>
          </div>
          <div className="detail-row">
            <div className="detail-label">Email Verification Status</div>
            <div className="detail-value">{user.email_verified ? "Verified" : "Unverified"}</div>
          </div>
          <div className="detail-row">
            <div className="detail-label">Account Status</div>
            <div className="detail-value">{user.disabled ? "Disabled" : "Active"}</div>
          </div>
        </div>

        <div className="modal-footer">
          <button type="button" className="secondary-btn" onClick={onClose}>Close</button>
          <button type="button" className="primary-btn" onClick={onToggleStatus} disabled={toggling}>
            {toggling ? <Loader2 size={18} className="spin" /> : user.disabled ? "Enable Account" : "Disable Account"}
          </button>
        </div>
      </div>
    </div>
  );
}

function AdminsPage() {
  const { showToast } = useToast();
  const [admins, setAdmins] = useState([]);
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [actionLoadingId, setActionLoadingId] = useState(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [adminToToggle, setAdminToToggle] = useState(null);

  async function loadAdmins() {
    setLoading(true);
    setError("");

    try {
      const nextAdmins = await listAdmins();
      setAdmins(nextAdmins);
    } catch (err) {
      setAdmins([]);
      setError(err.message || "Unable to load administrator accounts.");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    loadAdmins();
  }, []);

  const filteredAdmins = useMemo(() => {
    const query = search.trim().toLowerCase();
    if (!query) return admins;

    return admins.filter((admin) => {
      const text = `${admin.full_name || ""} ${admin.email || ""}`.toLowerCase();
      return text.includes(query);
    });
  }, [admins, search]);

  async function handleStatusToggle(admin) {
    setActionLoadingId(admin.id);
    try {
      await updateAdminStatus(admin.id, !admin.disabled);
      await loadAdmins();
      showToast(`Admin ${admin.disabled ? "enabled" : "disabled"} successfully.`, admin.disabled ? "success" : "error");
      return true;
    } catch (err) {
      setError(err.message || "Unable to update this administrator account right now.");
      return false;
    } finally {
      setActionLoadingId(null);
    }
  }

  return (
    <>
      <div className="page-heading">
        <div>
          <h3>Admins</h3>
          <p className="muted">Manage Heartshapers administrator accounts.</p>
        </div>
        <button className="primary-btn" onClick={() => setModalOpen(true)}>
          <Plus size={18} /> Add Admin
        </button>
      </div>

      <div className="toolbar">
        <div className="search-box user-search-box">
          <Search size={18} />
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search admins by name or email..."
          />
        </div>
      </div>

      {error && <div className="error-box page-error">{error}</div>}

      <div className="table-card">
        {loading ? (
          <div className="empty-state"><Loader2 className="spin" /> Loading admins...</div>
        ) : admins.length === 0 ? (
          <div className="empty-state">
            <ShieldCheck size={34} />
            <strong>No admin accounts found</strong>
            <span>There are currently no administrator accounts available.</span>
          </div>
        ) : filteredAdmins.length === 0 ? (
          <div className="empty-state">
            <Search size={34} />
            <strong>No matching admins</strong>
            <span>Try a different name or email address.</span>
          </div>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Full Name</th>
                  <th>Email</th>
                  <th>Role</th>
                  <th>Account Status</th>
                  <th>Date Created</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {filteredAdmins.map((admin) => (
                  <tr key={admin.id}>
                    <td>{admin.full_name || "Unnamed admin"}</td>
                    <td>{admin.email || "—"}</td>
                    <td>admin</td>
                    <td>
                      <span className={`status ${admin.disabled ? "disabled" : "active"}`}>
                        {admin.disabled ? <Lock size={13} /> : <Unlock size={13} />}
                        {admin.disabled ? "Disabled" : "Active"}
                      </span>
                    </td>
                    <td>{formatDate(admin.created_at)}</td>
                    <td>
                      <button
                        className="secondary-btn small danger"
                        onClick={() => setAdminToToggle(admin)}
                        disabled={actionLoadingId === admin.id}
                      >
                        {actionLoadingId === admin.id ? <Loader2 size={16} className="spin" /> : admin.disabled ? "Enable" : "Disable"}
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {modalOpen && (
        <CreateAdminModal onClose={() => setModalOpen(false)} onCreated={async () => {
          setModalOpen(false);
          await loadAdmins();
          showToast("Admin created successfully.", "success");
        }} />
      )}
      {adminToToggle && (
        <ConfirmModal
          title={`${adminToToggle.disabled ? "Enable" : "Disable"} Admin?`}
          message={`Are you sure you want to ${adminToToggle.disabled ? "enable" : "disable"} "${adminToToggle.full_name || adminToToggle.email || "this admin"}"?`}
          secondaryMessage={adminToToggle.disabled ? "The admin will regain access to the Admin application." : "The admin will no longer be able to access the Admin application."}
          actionLabel={adminToToggle.disabled ? "Enable" : "Disable"}
          tone={adminToToggle.disabled ? "success" : "danger"}
          onClose={() => setAdminToToggle(null)}
          onConfirm={() => handleStatusToggle(adminToToggle)}
        />
      )}
    </>
  );
}

function CreateAdminModal({ onClose, onCreated }) {
  const [form, setForm] = useState({
    full_name: "",
    email: "",
    password: "",
    confirmPassword: ""
  });
  const [fieldErrors, setFieldErrors] = useState({});
  const [busy, setBusy] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const [showConfirmPassword, setShowConfirmPassword] = useState(false);

  function updateField(field, value) {
    setForm((current) => ({ ...current, [field]: value }));
    setFieldErrors((current) => ({ ...current, [field]: "" }));
  }

  function validate() {
    const errors = {};
    if (!form.full_name.trim()) errors.full_name = "Full Name is required.";

    const trimmedEmail = form.email.trim();
    if (!trimmedEmail) errors.email = "Email is required.";
    else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmedEmail)) errors.email = "Enter a valid email address.";

    if (!form.password) errors.password = "Password is required.";
    else if (form.password.length < 8 || form.password.length > 16) errors.password = "Password must be 8-16 characters long.";
    else if (!/[^A-Za-z0-9]/.test(form.password)) errors.password = "Password must include at least one special character.";

    if (!form.confirmPassword) errors.confirmPassword = "Please confirm the password.";
    else if (form.confirmPassword !== form.password) errors.confirmPassword = "Passwords do not match.";

    return errors;
  }

  async function submit(e) {
    e.preventDefault();
    const nextErrors = validate();
    setFieldErrors(nextErrors);
    if (Object.keys(nextErrors).length > 0) return;

    setBusy(true);
    try {
      await createAdmin({
        full_name: form.full_name.trim(),
        email: form.email.trim(),
        password: form.password
      });
      onCreated();
    } catch (err) {
      const message = err.message || "Unable to create the administrator account. Please try again.";
      setFieldErrors({ submit: message });
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="modal-backdrop">
      <div className="modal user-modal">
        <div className="modal-header">
          <div>
            <h3>Add Admin</h3>
            <p className="muted">Create a new Heartshapers administrator account.</p>
          </div>
          <button className="icon-btn" onClick={onClose}><X size={20} /></button>
        </div>

        <form onSubmit={submit}>
          <div className="modal-body">
            {fieldErrors.submit && <div className="error-box">{fieldErrors.submit}</div>}

            <label>Full Name *</label>
            <input value={form.full_name} onChange={(e) => updateField("full_name", e.target.value)} placeholder="Enter full name" />
            {fieldErrors.full_name && <div className="field-error">{fieldErrors.full_name}</div>}

            <label>Email *</label>
            <input type="email" value={form.email} onChange={(e) => updateField("email", e.target.value)} placeholder="admin@example.com" />
            {fieldErrors.email && <div className="field-error">{fieldErrors.email}</div>}

            <label>Password *</label>
            <div className="password-field">
              <input
                type={showPassword ? "text" : "password"}
                value={form.password}
                onChange={(e) => updateField("password", e.target.value)}
                placeholder="Enter password"
              />
              <button type="button" className="password-toggle" onClick={() => setShowPassword((current) => !current)}>
                {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
              </button>
            </div>
            {fieldErrors.password && <div className="field-error">{fieldErrors.password}</div>}

            <label>Confirm Password *</label>
            <div className="password-field">
              <input
                type={showConfirmPassword ? "text" : "password"}
                value={form.confirmPassword}
                onChange={(e) => updateField("confirmPassword", e.target.value)}
                placeholder="Re-enter password"
              />
              <button type="button" className="password-toggle" onClick={() => setShowConfirmPassword((current) => !current)}>
                {showConfirmPassword ? <EyeOff size={18} /> : <Eye size={18} />}
              </button>
            </div>
            {fieldErrors.confirmPassword && <div className="field-error">{fieldErrors.confirmPassword}</div>}
          </div>

          <div className="modal-footer">
            <button type="button" className="secondary-btn" onClick={onClose}>Cancel</button>
            <button className="primary-btn" type="submit" disabled={busy}>
              {busy ? <><Loader2 size={18} className="spin" /> Creating...</> : <><Plus size={18} /> Create Admin</>}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

function AccessDeniedPage({ message = "You do not have permission to access this page." }) {
  return (
    <div className="settings-card access-card">
      <h3>Access denied</h3>
      <p className="muted">{message}</p>
    </div>
  );
}

function SettingsPage() {
  const [message, setMessage] = useState("");

  async function resetPassword() {
    const { data } = await supabase.auth.getUser();
    const email = data.user?.email;
    if (!email) return;

    const { error } = await supabase.auth.resetPasswordForEmail(email);
    setMessage(error ? error.message : "Password reset email sent.");
  }

  return (
    <div className="settings-card">
      <h3>Settings</h3>
      <p className="muted">Basic admin account settings.</p>
      <div className="setting-row">
        <div>
          <strong>Change password</strong>
          <p className="muted">Send a password reset link to the current admin email.</p>
        </div>
        <button className="secondary-btn" onClick={resetPassword}>Reset Password</button>
      </div>
      {message && <div className="success-box">{message}</div>}
    </div>
  );
}

function LoadingScreen() {
  return <div className="loading-screen"><Loader2 className="spin" size={30} /> Loading...</div>;
}

function getInitials(name) {
  const value = name || "U";
  const parts = value.split(/\s+/).filter(Boolean);
  if (parts.length >= 2) return `${parts[0][0]}${parts[1][0]}`.toUpperCase();
  return value.slice(0, 2).toUpperCase();
}

function formatDate(value) {
  if (!value) return "—";
  return new Intl.DateTimeFormat(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric"
  }).format(new Date(value));
}

export default App;