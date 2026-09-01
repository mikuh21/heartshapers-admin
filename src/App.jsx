import React, { useEffect, useMemo, useState } from "react";
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
  Users
} from "lucide-react";
import { supabase, COVER_BUCKET, PDF_BUCKET } from "./lib/supabase";
import { isAdminUser, listUsers, updateUserStatus } from "./lib/adminUsers";

const EMPTY_BOOK = {
  id: null,
  title: "",
  cover_image_url: "",
  pdf_url: "",
  pillar: "",
  subcategory: "",
  is_locked: false
};

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

  return <AdminApp session={session} />;
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

    const { error } = await supabase.auth.signInWithPassword({
      email: email.trim(),
      password
    });

    if (error) setError(error.message);
    setBusy(false);
  }

  return (
    <div className="login-page">
      <div className="login-card">
        <div className="brand-mark">H</div>
        <h1>HeartShapers</h1>
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

function AdminApp({ session }) {
  const [page, setPage] = useState("dashboard");
  const [mobileOpen, setMobileOpen] = useState(false);
  const canManageUsers = isAdminUser(session.user);

  async function logout() {
    await supabase.auth.signOut();
  }

  const title =
    page === "dashboard"
      ? "Dashboard"
      : page === "books"
        ? "Books"
        : page === "users"
          ? "Users"
          : "Settings";

  const subtitle =
    page === "dashboard"
      ? "Manage your HeartShapers content"
      : page === "books"
        ? "Manage your HeartShapers content"
        : page === "users"
          ? "Manage HeartShapers user accounts"
          : "Basic admin settings";

  return (
    <div className="app-shell">
      <aside className={`sidebar ${mobileOpen ? "open" : ""}`}>
        <div className="sidebar-brand">
          <div className="brand-mark small">H</div>
          <div>
            <strong>HeartShapers</strong>
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
          <button className="nav-item logout-item" onClick={logout}>
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
          <div>
            <h2>{title}</h2>
            <p>{subtitle}</p>
          </div>
          <div className="account">
            <div className="avatar">{(session.user.email || "A")[0].toUpperCase()}</div>
            <span>{session.user.email}</span>
          </div>
        </header>

        <div className="content">
          {page === "dashboard" && <Dashboard goBooks={() => setPage("books")} />}
          {page === "books" && <Books />}
          {page === "users" && <UsersPage canManageUsers={canManageUsers} />}
          {page === "settings" && <SettingsPage />}
        </div>
      </main>
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
          <p className="muted">A simple overview of your HeartShapers books.</p>
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
          <p>Add, edit, upload, and remove books from one simple page. Changes are saved directly to your Supabase database.</p>
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
  const [books, setBooks] = useState([]);
  const [search, setSearch] = useState("");
  const [pillar, setPillar] = useState("All");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [modal, setModal] = useState(null);
  const [selected, setSelected] = useState(null);

  async function loadBooks() {
    setLoading(true);
    setError("");

    const { data, error } = await supabase
      .from("books")
      .select("id,title,cover_image_url,pdf_url,pillar,subcategory,created_at,is_locked")
      .order("created_at", { ascending: false });

    if (error) setError(error.message);
    else setBooks(data || []);
    setLoading(false);
  }

  useEffect(() => {
    loadBooks();
  }, []);

  const pillars = useMemo(
    () => ["All", ...new Set(books.map((b) => b.pillar).filter(Boolean))],
    [books]
  );

  const filtered = books.filter((book) => {
    const text = `${book.title || ""} ${book.subcategory || ""} ${book.pillar || ""}`.toLowerCase();
    return text.includes(search.toLowerCase()) && (pillar === "All" || book.pillar === pillar);
  });

  async function deleteBook(book) {
    const confirmed = window.confirm(`Delete "${book.title}"? This cannot be undone.`);
    if (!confirmed) return;

    const { error } = await supabase.from("books").delete().eq("id", book.id);
    if (error) {
      setError(error.message);
      return;
    }

    setBooks((current) => current.filter((item) => item.id !== book.id));
  }

  return (
    <>
      <div className="page-heading">
        <div>
          <h3>Books</h3>
          <p className="muted">Manage the books stored in HeartShapers.</p>
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
          <select value={pillar} onChange={(e) => setPillar(e.target.value)}>
            {pillars.map((item) => <option key={item}>{item}</option>)}
          </select>
          <ChevronDown size={16} />
        </div>
      </div>

      {error && <div className="error-box page-error">{error}</div>}

      <div className="table-card">
        {loading ? (
          <div className="empty-state"><Loader2 className="spin" /> Loading books...</div>
        ) : filtered.length === 0 ? (
          <div className="empty-state">
            <BookOpen size={34} />
            <strong>No books found</strong>
            <span>Add a book or change your search.</span>
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
                        <button className="icon-btn danger" title="Delete" onClick={() => deleteBook(book)}>
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
          onSaved={() => {
            setModal(null);
            loadBooks();
          }}
        />
      )}
    </>
  );
}

function BookModal({ book, onClose, onSaved }) {
  const [form, setForm] = useState(book ? { ...book } : { ...EMPTY_BOOK });
  const [coverFile, setCoverFile] = useState(null);
  const [pdfFile, setPdfFile] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  function update(field, value) {
    setForm((current) => ({ ...current, [field]: value }));
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

    if (!form.title.trim()) {
      setError("Please enter a book title.");
      return;
    }

    if (!form.pillar.trim()) {
      setError("Please enter a pillar.");
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
        cover_image_url: coverUrl,
        pdf_url: pdfUrl,
        pillar: form.pillar.trim(),
        subcategory: form.subcategory.trim() || null,
        is_locked: Boolean(form.is_locked)
      };

      let result;

      if (form.id) {
        result = await supabase
          .from("books")
          .update(payload)
          .eq("id", form.id)
          .select()
          .single();
      } else {
        result = await supabase
          .from("books")
          .insert(payload)
          .select()
          .single();
      }

      if (result.error) throw result.error;

      onSaved(result.data);
    } catch (err) {
      setError(err.message || "Something went wrong.");
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
            <p className="muted">{form.id ? "Update this book." : "Add a book to HeartShapers."}</p>
          </div>
          <button className="icon-btn" onClick={onClose}><X size={20} /></button>
        </div>

        <form onSubmit={saveBook}>
          <div className="modal-body">
            {error && <div className="error-box">{error}</div>}

            <label>Book Title *</label>
            <input value={form.title} onChange={(e) => update("title", e.target.value)} placeholder="Enter book title" />

            <label>Pillar *</label>
            <input value={form.pillar} onChange={(e) => update("pillar", e.target.value)} placeholder="Example: Family, Work, Ministry" />

            <label>Subcategory</label>
            <input value={form.subcategory || ""} onChange={(e) => update("subcategory", e.target.value)} placeholder="Enter subcategory" />

            <div className="file-grid">
              <FileInput
                label="Cover Image"
                accept="image/*"
                file={coverFile}
                current={form.cover_image_url}
                icon={<ImageIcon size={19} />}
                onChange={setCoverFile}
              />
              <FileInput
                label="Book PDF"
                accept="application/pdf,.pdf"
                file={pdfFile}
                current={form.pdf_url}
                icon={<FileText size={19} />}
                onChange={setPdfFile}
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

function FileInput({ label, accept, file, current, icon, onChange }) {
  return (
    <div>
      <label>{label}</label>
      <label className="file-input">
        <input type="file" accept={accept} onChange={(e) => onChange(e.target.files?.[0] || null)} />
        {icon}
        <span>{file ? file.name : current ? "File already uploaded" : "Choose file"}</span>
      </label>
    </div>
  );
}

function UsersPage({ canManageUsers }) {
  if (!canManageUsers) {
    return (
      <div className="settings-card access-card">
        <h3>Access denied</h3>
        <p className="muted">You do not have permission to manage user accounts in HeartShapers Admin.</p>
      </div>
    );
  }

  const [users, setUsers] = useState([]);
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [actionLoadingId, setActionLoadingId] = useState(null);
  const [selectedUser, setSelectedUser] = useState(null);

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
    const targetState = user.disabled ? "re-enable" : "disable";
    const confirmed = window.confirm(`Are you sure you want to ${targetState} this user?\n\n${user.full_name || user.email}`);
    if (!confirmed) return;

    setActionLoadingId(user.id);
    try {
      const updatedUser = await updateUserStatus(user.id, !user.disabled);
      if (updatedUser) {
        setUsers((current) => current.map((item) => item.id === updatedUser.id ? updatedUser : item));
        setSelectedUser((currentUser) => (currentUser && currentUser.id === updatedUser.id ? updatedUser : currentUser));
      }
    } catch (err) {
      setError(err.message || "Unable to update this user account right now.");
    } finally {
      setActionLoadingId(null);
    }
  }

  return (
    <>
      <div className="page-heading">
        <div>
          <h3>Users</h3>
          <p className="muted">Manage HeartShapers user accounts.</p>
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
                          onClick={() => handleStatusToggle(user)}
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
          onToggleStatus={() => handleStatusToggle(selectedUser)}
          toggling={actionLoadingId === selectedUser.id}
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