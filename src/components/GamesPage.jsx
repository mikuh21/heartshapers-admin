import React, { useEffect, useMemo, useRef, useState } from "react";
import pdfWorkerUrl from "pdfjs-dist/build/pdf.worker.min.mjs?url";
import {
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  FileText,
  Gamepad2,
  ImagePlus,
  Loader2,
  Pencil,
  Plus,
  Search,
  Trash2,
  Users,
  X,
  ChevronUp
} from "lucide-react";
import { logAdminAction } from "../lib/adminAudit";
import { getGameUserAccess, updateGameUserAccess } from "../lib/adminUsers";
import {
  createGameCard,
  createPdfGame,
  createGameRule,
  deleteGame,
  loadGameAccess,
  listGamesWithCounts,
  loadGameDetails,
  loadPlacementNames,
  updateGameAccess,
  updateGameCard,
  updateGameRule
} from "../lib/games";

const CARD_PAGE_SIZE = 20;
const MAX_GAME_COVER_SIZE = 10 * 1024 * 1024;
const MAX_GAME_PDF_SIZE = 50 * 1024 * 1024;

function formatMetadata(metadata) {
  return JSON.stringify(metadata ?? {}, null, 2);
}

async function renderPdfPage(page, maxDimension, outputType = "image/jpeg") {
  const initialViewport = page.getViewport({ scale: 1 });
  const scale = Math.min(maxDimension / initialViewport.width, maxDimension / initialViewport.height);
  const viewport = page.getViewport({ scale });
  const canvas = document.createElement("canvas");
  canvas.width = Math.ceil(viewport.width);
  canvas.height = Math.ceil(viewport.height);
  const context = canvas.getContext("2d");
  if (!context) throw new Error("Unable to prepare a PDF page preview.");

  await page.render({ canvasContext: context, viewport }).promise;
  const blob = await new Promise((resolve, reject) => {
    canvas.toBlob((result) => {
      if (result) resolve(result);
      else reject(new Error("Unable to render a PDF page image."));
    }, outputType, outputType === "image/jpeg" ? 0.9 : undefined);
  });
  canvas.width = 0;
  canvas.height = 0;
  return blob;
}

function makePairs(pairs, count) {
  return Array.from({ length: count }, (_, index) => ({
    left: pairs?.[index]?.left || "",
    right: pairs?.[index]?.right || "",
    underlined: Array.isArray(pairs?.[index]?.underlined)
      ? pairs[index].underlined.join("\n")
      : ""
  }));
}

function getCardEditorForm(game, card) {
  const metadata = card?.metadata && typeof card.metadata === "object" ? card.metadata : {};
  const pairs = Array.isArray(metadata.pairs) ? metadata.pairs : [];
  const source = metadata.source_card && typeof metadata.source_card === "object"
    ? metadata.source_card
    : {};

  switch (game.game_type) {
    case "bible_action":
      return { pairs: makePairs(pairs, 4) };
    case "bible_draw":
      return {
        prompt: card?.front_text || pairs[0]?.left || "",
        items: Array.from({ length: 5 }, (_, index) => pairs[index]?.left || "")
      };
    case "bible_groups":
      return {
        heading: card?.front_text || pairs[0]?.left || "",
        entries: pairs.slice(1).map((pair) => pair.left || "").length
          ? pairs.slice(1).map((pair) => pair.left || "")
          : Array.from({ length: 5 }, () => "")
      };
    case "bible_proverbs":
      return {
        verses: Array.from({ length: 2 }, (_, index) => {
          const sourceVerse = source.verses?.[index] || {};
          return {
            text: sourceVerse.verse || pairs[index]?.left || "",
            reference: sourceVerse.reference || "",
            originalLeft: pairs[index]?.left || "",
            right: pairs[index]?.right || "",
            underlined: Array.isArray(pairs[index]?.underlined)
              ? pairs[index].underlined.join("\n")
              : Array.isArray(sourceVerse.underlined)
                ? sourceVerse.underlined.join("\n")
                : ""
          };
        })
      };
    case "bible_question":
      return {
        category: metadata.category || source.category || "",
        entries: Array.from({ length: 4 }, (_, index) => pairs[index]?.left || "")
      };
    case "bible_talk":
      return {
        target: card?.front_text || pairs[0]?.left || "",
        clues: pairs.slice(1).map((pair) => pair.left || "").length
          ? pairs.slice(1).map((pair) => pair.left || "")
          : Array.from({ length: 5 }, () => "")
      };
    case "inspirational_talk_1":
      return {
        quote: pairs[0]?.left || card?.front_text || "",
        author: (pairs[1]?.left || "").replace(/^-\s*/, ""),
        question: pairs[2]?.left || ""
      };
    case "inspirational_talk_2":
      return {
        quote: pairs[0]?.left || card?.front_text || "",
        question: pairs[1]?.left || ""
      };
    default:
      return {};
  }
}

function buildGameCardData(game, form, card, sortOrder) {
  const metadata = card?.metadata && typeof card.metadata === "object"
    ? { ...card.metadata }
    : {};
  const existingSource = metadata.source_card && typeof metadata.source_card === "object"
    ? metadata.source_card
    : {};
  const cardId = sortOrder;
  const sourceItems = (items) => items.map((item) => item.trim()).filter(Boolean);
  let pairs = [];
  let frontText = "";
  let backText = card?.back_text || "";
  let sourceCard = existingSource;
  const oldPairs = Array.isArray(metadata.pairs) ? metadata.pairs : [];
  const mergePair = (index, values) => ({
    ...(oldPairs[index] || {}),
    right: oldPairs[index]?.right ?? "",
    ...values
  });

  switch (game.game_type) {
    case "bible_action":
      pairs = form.pairs.map(({ left, right }, index) => mergePair(index, {
        left: left.trim(),
        right: right.trim()
      }));
      frontText = pairs[0].left;
      backText = pairs[0].right;
      sourceCard = { ...existingSource, pairs };
      break;
    case "bible_draw": {
      const items = form.items.map((item) => item.trim());
      pairs = items.map((left, index) => mergePair(index, { left }));
      frontText = form.prompt.trim();
      sourceCard = { ...existingSource, id: existingSource.id ?? cardId, items: items.filter(Boolean) };
      break;
    }
    case "bible_groups": {
      const entries = sourceItems(form.entries);
      const heading = form.heading.trim();
      pairs = [
        mergePair(0, { left: heading }),
        ...entries.map((left, index) => mergePair(index + 1, { left }))
      ];
      frontText = heading;
      sourceCard = {
        ...existingSource,
        id: existingSource.id ?? cardId,
        category: heading,
        items: entries
      };
      break;
    }
    case "bible_proverbs": {
      const verses = form.verses.map((verse, index) => {
        const underlined = verse.underlined.split(/\r?\n/).map((word) => word.trim()).filter(Boolean);
        const text = verse.text.trim();
        const reference = verse.reference.trim();
        const sourceVerse = existingSource.verses?.[index] || {};
        const unchanged = text === sourceVerse.verse && reference === sourceVerse.reference;
        const left = unchanged
          ? verse.originalLeft
          : reference ? `${text} - ${reference}` : text;
        const oldVerse = sourceVerse;
        pairs.push(mergePair(index, { left, right: verse.right.trim(), underlined }));
        return { ...oldVerse, verse: text, reference, underlined };
      });
      frontText = pairs[0].left;
      sourceCard = { ...existingSource, id: existingSource.id ?? cardId, verses };
      break;
    }
    case "bible_question": {
      const entries = form.entries.map((item) => item.trim());
      pairs = entries.map((left, index) => mergePair(index, { left }));
      frontText = pairs[0].left;
      metadata.category = form.category.trim();
      sourceCard = {
        ...existingSource,
        id: existingSource.id ?? cardId,
        category: form.category.trim(),
        items: entries.filter(Boolean)
      };
      break;
    }
    case "bible_talk": {
      const clues = sourceItems(form.clues);
      pairs = [
        mergePair(0, { left: form.target.trim() }),
        ...clues.map((left, index) => mergePair(index + 1, { left }))
      ];
      frontText = form.target.trim();
      sourceCard = {
        ...existingSource,
        id: existingSource.id ?? cardId,
        term: form.target.trim(),
        clues
      };
      break;
    }
    case "inspirational_talk_1": {
      const quote = form.quote.trim();
      const author = form.author.trim();
      const question = form.question.trim();
      pairs = [
        mergePair(0, { left: quote }),
        mergePair(1, { left: author ? `- ${author}` : "" }),
        mergePair(2, { left: question })
      ];
      frontText = quote;
      sourceCard = { ...existingSource, id: existingSource.id ?? cardId, quote, author, question };
      break;
    }
    case "inspirational_talk_2": {
      const quote = form.quote.trim();
      const question = form.question.trim();
      pairs = [mergePair(0, { left: quote }), mergePair(1, { left: question })];
      frontText = quote;
      sourceCard = { ...existingSource, id: existingSource.id ?? cardId, quote, question };
      break;
    }
    default:
      throw new Error("This game type does not support card editing.");
  }

  if (!card && game.game_type !== "bible_action") {
    metadata.id = cardId;
    metadata.contentItemId = game.id;
    metadata.sortOrder = sortOrder;
  }
  metadata.pairs = pairs;
  metadata.source_card = sourceCard;

  return {
    sort_order: sortOrder,
    front_text: frontText,
    back_text: backText,
    metadata
  };
}

function validateGameCardForm(gameType, form) {
  const errors = {};
  const requireValue = (value, key, label) => {
    if (!String(value ?? "").trim()) errors[key] = `${label} is required.`;
  };

  switch (gameType) {
    case "bible_action":
      form.pairs.forEach((pair, index) => {
        requireValue(pair.left, `pairs.${index}.left`, `Pair ${index + 1} left text`);
        requireValue(pair.right, `pairs.${index}.right`, `Pair ${index + 1} right text`);
      });
      break;
    case "bible_draw":
      requireValue(form.prompt, "prompt", "Prompt/list label");
      form.items.forEach((item, index) => requireValue(item, `items.${index}`, `Drawing item ${index + 1}`));
      break;
    case "bible_groups":
      requireValue(form.heading, "heading", "List heading");
      if (!form.entries.some((entry) => entry.trim())) errors.entries = "Enter at least one list entry.";
      break;
    case "bible_proverbs":
      form.verses.forEach((verse, index) => {
        requireValue(verse.text, `verses.${index}.text`, `Verse ${index + 1}`);
        requireValue(verse.underlined, `verses.${index}.underlined`, `Verse ${index + 1} underlined words`);
      });
      break;
    case "bible_question":
      requireValue(form.category, "category", "Category");
      form.entries.forEach((entry, index) => requireValue(entry, `entries.${index}`, `Entry ${index + 1}`));
      break;
    case "bible_talk":
      requireValue(form.target, "target", "Target word/topic");
      if (!form.clues.some((clue) => clue.trim())) errors.clues = "Enter at least one prohibited clue.";
      break;
    case "inspirational_talk_1":
      requireValue(form.quote, "quote", "Quote");
      requireValue(form.author, "author", "Author");
      requireValue(form.question, "question", "Question");
      break;
    case "inspirational_talk_2":
      requireValue(form.quote, "quote", "Quote");
      requireValue(form.question, "question", "Question");
      break;
    default:
      errors.form = "This game type does not support card editing.";
  }
  return errors;
}

export default function GamesPage({ canManageGames, ConfirmModal, showToast }) {
  const [games, setGames] = useState([]);
  const [pillars, setPillars] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [search, setSearch] = useState("");
  const [accessFilter, setAccessFilter] = useState("all");
  const [pillarFilter, setPillarFilter] = useState("all");
  const [selectedGame, setSelectedGame] = useState(null);
  const [addGameOpen, setAddGameOpen] = useState(false);
  const [accessGame, setAccessGame] = useState(null);
  const [deleteTarget, setDeleteTarget] = useState(null);
  const [refreshKey, setRefreshKey] = useState(0);

  useEffect(() => {
    let active = true;
    setLoading(true);
    setError("");
    listGamesWithCounts()
      .then((result) => {
        if (!active) return;
        setGames(result.games);
        setPillars(result.pillars);
      })
      .catch((loadError) => {
        if (active) setError(loadError.message || "Unable to load games.");
      })
      .finally(() => {
        if (active) setLoading(false);
      });

    return () => {
      active = false;
    };
  }, [refreshKey]);

  const filteredGames = useMemo(() => {
    const query = search.trim().toLowerCase();
    return games.filter((game) => {
      const matchesSearch = !query ||
        `${game.title || ""} ${game.game_type || ""}`.toLowerCase().includes(query);
      const matchesAccess = accessFilter === "all" ||
        game.is_locked === (accessFilter === "locked");
      const matchesPillar = pillarFilter === "all" ||
        game.pillarIds.includes(pillarFilter);
      return matchesSearch && matchesAccess && matchesPillar;
    });
  }, [games, search, accessFilter, pillarFilter]);

  async function confirmGameDeletion() {
    if (!deleteTarget) return false;

    try {
      await deleteGame(deleteTarget.id);
      await logAdminAction({
        action: "game_deleted",
        targetType: "game",
        targetId: deleteTarget.id,
        targetName: deleteTarget.title
      });
      setSelectedGame((current) => current?.id === deleteTarget.id ? null : current);
      setAccessGame((current) => current?.id === deleteTarget.id ? null : current);
      setDeleteTarget(null);
      setRefreshKey((current) => current + 1);
      showToast(`${deleteTarget.title} deleted successfully.`, "success");
      return true;
    } catch (deleteError) {
      showToast(deleteError.message || "Unable to delete this game.", "error");
      throw deleteError;
    }
  }

  if (!canManageGames) {
    return <div className="settings-card access-card"><h3>Access denied</h3><p className="muted">You do not have permission to manage games.</p></div>;
  }

  return (
    <>
      <div className="page-heading">
        <div>
          <h3>Games</h3>
          <p className="muted">Manage the games stored in Heartshapers.</p>
        </div>
        <button type="button" className="primary-btn" onClick={() => setAddGameOpen(true)}>
          <Plus size={18} /> Add Game
        </button>
      </div>

      <div className="toolbar games-toolbar">
        <div className="search-box">
          <Search size={18} />
          <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search games..." />
        </div>
        <div className="select-box">
          <select value={accessFilter} onChange={(event) => setAccessFilter(event.target.value)} aria-label="Filter games by access">
            <option value="all">All access</option>
            <option value="free">Free</option>
            <option value="locked">Locked</option>
          </select>
          <ChevronDown size={16} />
        </div>
        <div className="select-box">
          <select value={pillarFilter} onChange={(event) => setPillarFilter(event.target.value)} aria-label="Filter games by pillar">
            <option value="all">All pillars</option>
            {pillars.map((pillar) => <option key={pillar.id} value={pillar.id}>{pillar.name}</option>)}
          </select>
          <ChevronDown size={16} />
        </div>
      </div>

      {error && <div className="error-box page-error">{error}</div>}
      <div className="table-card">
        {loading ? (
          <div className="empty-state"><Loader2 className="spin" /><span>Loading games...</span></div>
        ) : filteredGames.length === 0 ? (
          <div className="empty-state">
            <Gamepad2 size={34} />
            <strong>{games.length === 0 ? "No games found" : "No matching games"}</strong>
            <span>{games.length === 0 ? "Games stored in Supabase will appear here." : "Try changing your search or filters."}</span>
          </div>
        ) : (
          <div className="table-wrap">
            <table className="games-table">
              <thead><tr><th>Game</th><th className="games-cards-cell">Cards</th><th className="games-access-cell">Access</th><th className="games-actions-cell">Actions</th></tr></thead>
              <tbody>
                {filteredGames.map((game) => (
                  <tr key={game.id}>
                    <td><div className="games-name-cell">{game.cover_display_url || game.cover_image_url ? <img src={game.cover_display_url || game.cover_image_url} alt="" /> : <div className="cover-placeholder"><Gamepad2 size={20} /></div>}<div><strong>{game.title}</strong><span>{game.subtitle || game.id}</span></div></div></td>
                    <td className="games-cards-cell">{game.cardCount}</td>
                    <td className="games-access-cell">
                      <button type="button" className="icon-btn" title="User Access" aria-label={`Manage user access for ${game.title}`} onClick={() => setAccessGame(game)}>
                        <Users size={17} />
                      </button>
                    </td>
                    <td className="games-actions-cell">
                      <div className="actions">
                        <button type="button" className="icon-btn" title="View / Edit" aria-label={`View or edit ${game.title}`} onClick={() => setSelectedGame(game)}>
                          <Pencil size={17} />
                        </button>
                        <button type="button" className="icon-btn danger" title="Delete" aria-label={`Delete ${game.title}`} onClick={() => setDeleteTarget(game)}>
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

      {selectedGame && (
        <GameDetailsModal
          key={selectedGame.id}
          game={selectedGame}
          onClose={() => setSelectedGame(null)}
          onSaved={(updatedGame) => {
            setGames((current) => current.map((game) => game.id === updatedGame.id
              ? { ...game, ...updatedGame }
              : game));
            setSelectedGame((current) => current?.id === updatedGame.id
              ? { ...current, ...updatedGame }
              : current);
            setRefreshKey((current) => current + 1);
          }}
          showToast={showToast}
        />
      )}
      {addGameOpen && (
        <AddGameModal
          existingGames={games}
          onClose={() => setAddGameOpen(false)}
          onCreated={async (game) => {
            const auditSucceeded = await logAdminAction({
              action: "game_created",
              targetType: "game",
              targetId: game.id,
              targetName: game.title,
              details: {
                "Game Type": "PDF Deck",
                ...(game.subtitle ? { Subtitle: game.subtitle } : {}),
                ...(game.description ? { Description: game.description } : {}),
                "Sort Order": game.sort_order,
                "Initial Access": "Locked"
              }
            }).catch((auditError) => {
              console.error("Game creation audit logging failed.", {
                code: auditError?.code || auditError?.name || "AUDIT_LOG_FAILED"
              });
              return false;
            });
            setAddGameOpen(false);
            setRefreshKey((current) => current + 1);
            showToast(
              auditSucceeded
                ? `${game.title} created as locked.`
                : "Game created as locked, but its audit log could not be saved.",
              auditSucceeded ? "success" : "error"
            );
          }}
          nextSortOrder={games.reduce((max, game) => Math.max(max, Number(game.sort_order) || 0), 0) + 1}
          showToast={showToast}
        />
      )}
      {accessGame && (
        <GameUserAccessModal
          key={accessGame.id}
          game={accessGame}
          onClose={() => setAccessGame(null)}
          showToast={showToast}
        />
      )}
      {deleteTarget && (
        <ConfirmModal
          title="Delete Game?"
          message={`Are you sure you want to delete "${deleteTarget.title || "Untitled"}"?`}
          secondaryMessage="This may permanently remove its associated rules, cards, placements, and user access settings. Any remaining game storage assets prevent deletion."
          actionLabel="Delete"
          busyLabel="Deleting..."
          tone="danger"
          onClose={() => setDeleteTarget(null)}
          onConfirm={confirmGameDeletion}
        />
      )}
    </>
  );
}

function GameUserAccessModal({ game, onClose, showToast }) {
  const showToastRef = useRef(showToast);
  showToastRef.current = showToast;
  const [users, setUsers] = useState([]);
  const [purchasedUserIds, setPurchasedUserIds] = useState(() => new Set());
  const [accessOverrides, setAccessOverrides] = useState(() => new Map());
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(false);
  const [search, setSearch] = useState("");
  const [updatingUserIds, setUpdatingUserIds] = useState(() => new Set());

  useEffect(() => {
    let active = true;

    getGameUserAccess(game.id)
      .then((access) => {
        if (!active) return;
        setUsers(access.users);
        setPurchasedUserIds(new Set(access.purchasedUserIds));
        setAccessOverrides(new Map(access.accessOverrides.map((entry) => [
          entry.user_id,
          entry.access_status
        ])));
      })
      .catch((error) => {
        console.error("Unable to load game user access.", {
          code: error?.code || error?.name || "GAME_ACCESS_LOAD_FAILED"
        });
        if (active) {
          setLoadError(true);
          showToastRef.current("Unable to load game user access information.", "error");
        }
      })
      .finally(() => {
        if (active) setLoading(false);
      });

    return () => {
      active = false;
    };
  }, [game.id]);

  async function changeUserAccess(user, accessStatus) {
    if (updatingUserIds.has(user.id)) return;
    setUpdatingUserIds((current) => new Set(current).add(user.id));
    try {
      const savedStatus = await updateGameUserAccess({
        gameId: game.id,
        userId: user.id,
        accessStatus
      });
      setAccessOverrides((current) => new Map(current).set(user.id, savedStatus));
      showToastRef.current("Game user access updated successfully.", "success");
    } catch (error) {
      showToastRef.current(error.message || "Unable to update game user access.", "error");
    } finally {
      setUpdatingUserIds((current) => {
        const next = new Set(current);
        next.delete(user.id);
        return next;
      });
    }
  }

  const query = search.trim().toLowerCase();
  const visibleUsers = users.filter((user) =>
    !query || `${user.full_name || ""} ${user.email || ""}`.toLowerCase().includes(query)
  );
  const statusForUser = (userId) => purchasedUserIds.has(userId)
    ? "Paid"
    : accessOverrides.get(userId) || (game.is_locked ? "locked" : "free");

  return (
    <div className="modal-backdrop">
      <div className="modal user-access-modal" role="dialog" aria-modal="true" aria-labelledby="game-user-access-title">
        <div className="modal-header">
          <div>
            <h3 id="game-user-access-title">User Access</h3>
            <p className="muted">{game.title}</p>
          </div>
          <button type="button" className="icon-btn" onClick={onClose} aria-label="Close game user access">
            <X size={20} />
          </button>
        </div>
        <div className="user-access-content">
          {loading ? (
            <div className="empty-state small-empty"><Loader2 className="spin" size={18} /> Loading user access...</div>
          ) : loadError ? (
            <div className="empty-state small-empty">Access data is unavailable. Close and reopen this dialog to retry.</div>
          ) : users.length === 0 ? (
            <div className="empty-state small-empty">No registered users found.</div>
          ) : (
            <>
              <div className="user-access-toolbar">
                <div className="search-box user-access-search">
                  <Search size={18} />
                  <input
                    type="search"
                    value={search}
                    onChange={(event) => setSearch(event.target.value)}
                    placeholder="Search users..."
                    aria-label="Search users by name or email"
                  />
                </div>
              </div>
              {visibleUsers.length === 0 ? (
                <div className="empty-state small-empty">No users match this search.</div>
              ) : (
                <div className="user-access-list" role="list">
                  <div className="user-access-row user-access-heading" aria-hidden="true">
                    <span>User</span>
                    <span>Email</span>
                    <span>Access</span>
                  </div>
                  {visibleUsers.map((user) => {
                    const isPaid = purchasedUserIds.has(user.id);
                    const status = statusForUser(user.id);
                    const displayStatus = status === "Paid" ? "Paid" : status === "free" ? "Free" : "Locked";
                    return (
                      <div className="user-access-row" role="listitem" key={user.id}>
                        <strong>{user.full_name || "Unnamed user"}</strong>
                        <span className="user-access-email">{user.email || "—"}</span>
                        <select
                          className={`user-access-status-select status ${displayStatus.toLowerCase()}`}
                          value={isPaid ? "paid" : status}
                          disabled={isPaid || updatingUserIds.has(user.id)}
                          onChange={(event) => changeUserAccess(user, event.target.value)}
                          aria-label={`Access status for ${user.full_name || user.email} for ${game.title}`}
                        >
                          <option value="locked">Locked</option>
                          <option value="free">Free</option>
                          <option value="paid" disabled={!isPaid}>Paid</option>
                        </select>
                      </div>
                    );
                  })}
                </div>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
}

function AddGameModal({ existingGames, nextSortOrder, onClose, onCreated, showToast }) {
  const [form, setForm] = useState({
    title: "",
    subtitle: "",
    rules: ""
  });
  const [step, setStep] = useState(1);
  const [gameId, setGameId] = useState("");
  const [errors, setErrors] = useState({});
  const [saving, setSaving] = useState(false);
  const [coverFile, setCoverFile] = useState(null);
  const [coverPreviewUrl, setCoverPreviewUrl] = useState("");
  const [pdfFile, setPdfFile] = useState(null);
  const [pdfDocument, setPdfDocument] = useState(null);
  const [pdfPages, setPdfPages] = useState([]);
  const [selectedPageNumbers, setSelectedPageNumbers] = useState([]);
  const [pdfLoading, setPdfLoading] = useState(false);
  const [pdfProgress, setPdfProgress] = useState({ current: 0, total: 0 });
  const pdfDocumentRef = useRef(null);
  const pdfjsLibRef = useRef(null);
  const pdfLoadIdRef = useRef(0);
  const previewUrlsRef = useRef([]);
  const coverPreviewUrlRef = useRef("");

  useEffect(() => () => {
    pdfLoadIdRef.current += 1;
    previewUrlsRef.current.forEach((url) => URL.revokeObjectURL(url));
    if (coverPreviewUrlRef.current) URL.revokeObjectURL(coverPreviewUrlRef.current);
    if (pdfDocumentRef.current) {
      pdfDocumentRef.current.destroy().catch((error) => {
        console.error("PDF preview cleanup failed.", { message: error?.message });
      });
    }
  }, []);

  function clearPdfPreview() {
    pdfLoadIdRef.current += 1;
    setPdfLoading(false);
    setPdfFile(null);
    previewUrlsRef.current.forEach((url) => URL.revokeObjectURL(url));
    previewUrlsRef.current = [];
    if (pdfDocumentRef.current) {
      pdfDocumentRef.current.destroy().catch((error) => {
        console.error("PDF preview cleanup failed.", { message: error?.message });
      });
    }
    pdfDocumentRef.current = null;
    setPdfDocument(null);
    setPdfPages([]);
    setSelectedPageNumbers([]);
    setPdfProgress({ current: 0, total: 0 });
  }

  function chooseCover(event) {
    const file = event.target.files?.[0] || null;
    event.target.value = "";
    if (file && !["image/jpeg", "image/png", "image/webp"].includes(file.type)) {
      if (coverPreviewUrlRef.current) URL.revokeObjectURL(coverPreviewUrlRef.current);
      coverPreviewUrlRef.current = "";
      setCoverPreviewUrl("");
      setCoverFile(null);
      setErrors((current) => ({ ...current, cover: "Choose a JPEG, PNG, or WebP cover image." }));
      return;
    }
    if (file && file.size > MAX_GAME_COVER_SIZE) {
      if (coverPreviewUrlRef.current) URL.revokeObjectURL(coverPreviewUrlRef.current);
      coverPreviewUrlRef.current = "";
      setCoverPreviewUrl("");
      setCoverFile(null);
      setErrors((current) => ({ ...current, cover: "Cover images must be 10 MB or smaller." }));
      return;
    }
    if (coverPreviewUrlRef.current) URL.revokeObjectURL(coverPreviewUrlRef.current);
    coverPreviewUrlRef.current = file ? URL.createObjectURL(file) : "";
    setCoverPreviewUrl(coverPreviewUrlRef.current);
    setCoverFile(file);
    setErrors((current) => ({ ...current, cover: "" }));
  }

  async function choosePdf(event) {
    const file = event.target.files?.[0] || null;
    event.target.value = "";
    clearPdfPreview();
    setPdfFile(null);
    setErrors((current) => ({ ...current, pdf: "", pages: "" }));
    if (!file) return;
    if (!file.type.includes("pdf") && !file.name.toLowerCase().endsWith(".pdf")) {
      setErrors((current) => ({ ...current, pdf: "Choose a PDF file." }));
      return;
    }
    if (file.size > MAX_GAME_PDF_SIZE) {
      setErrors((current) => ({ ...current, pdf: "PDF files must be 50 MB or smaller." }));
      return;
    }

    const loadId = pdfLoadIdRef.current;
    setPdfLoading(true);
    try {
      setPdfFile(file);
      if (!pdfjsLibRef.current) {
        pdfjsLibRef.current = await import("pdfjs-dist");
        pdfjsLibRef.current.GlobalWorkerOptions.workerSrc = pdfWorkerUrl;
      }
      const task = pdfjsLibRef.current.getDocument({ data: new Uint8Array(await file.arrayBuffer()) });
      const document = await task.promise;
      if (!Number.isInteger(document.numPages) || document.numPages < 1) {
        await document.destroy();
        throw new Error("This PDF does not contain any renderable pages.");
      }
      if (loadId !== pdfLoadIdRef.current) {
        await document.destroy();
        return;
      }
      pdfDocumentRef.current = document;
      setPdfDocument(document);
      setPdfProgress({ current: 0, total: document.numPages });
      const pages = [];
      for (let pageNumber = 1; pageNumber <= document.numPages; pageNumber += 1) {
        if (loadId !== pdfLoadIdRef.current) {
          await document.destroy();
          return;
        }
        const page = await document.getPage(pageNumber);
        const previewBlob = await renderPdfPage(page, 240);
        const previewUrl = URL.createObjectURL(previewBlob);
        previewUrlsRef.current.push(previewUrl);
        pages.push({ pageNumber, previewUrl });
        setPdfPages([...pages]);
        setPdfProgress({ current: pageNumber, total: document.numPages });
      }
      setSelectedPageNumbers(Array.from({ length: document.numPages }, (_, index) => index + 1));
    } catch (error) {
      if (loadId === pdfLoadIdRef.current) {
        console.error("PDF page preview failed.", { message: error?.message });
        setErrors((current) => ({ ...current, pdf: "Unable to read this PDF. Choose another file." }));
        clearPdfPreview();
      }
    } finally {
      if (loadId === pdfLoadIdRef.current) setPdfLoading(false);
    }
  }

  function togglePdfPage(pageNumber, checked) {
    setSelectedPageNumbers((current) => checked
      ? [...current, pageNumber]
      : current.filter((selected) => selected !== pageNumber));
    setErrors((current) => ({ ...current, pages: "" }));
  }

  function movePdfPage(pageNumber, direction) {
    setSelectedPageNumbers((current) => {
      const index = current.indexOf(pageNumber);
      const destination = index + direction;
      if (index < 0 || destination < 0 || destination >= current.length) return current;
      const next = [...current];
      [next[index], next[destination]] = [next[destination], next[index]];
      return next;
    });
  }

  function update(field, value) {
    setForm((current) => ({ ...current, [field]: value }));
    if (field === "title") setGameId("");
    setErrors((current) => {
      if (!current[field]) return current;
      const next = { ...current };
      delete next[field];
      return next;
    });
  }

  function buildGameId(title) {
    const slug = title.toLowerCase().normalize("NFKD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 48);
    return `game-${slug || "custom"}-${crypto.randomUUID()}`;
  }

  function validateDetails() {
    const nextErrors = {};
    const title = form.title.trim();
    if (!title) nextErrors.title = "Game title is required.";
    else if (existingGames.some((game) => game.title?.trim().toLocaleLowerCase() === title.toLocaleLowerCase())) {
      nextErrors.title = "A game with this title already exists.";
    }
    if (!form.rules.trim()) nextErrors.rules = "Game rules are required.";
    if (!coverFile) nextErrors.cover = "Upload a separate game cover image.";
    if (!pdfFile || !pdfDocument) nextErrors.pdf = "Upload a valid game content PDF.";
    if (selectedPageNumbers.length === 0) nextErrors.pages = "Select at least one PDF page for the card deck.";
    setErrors(nextErrors);
    return Object.keys(nextErrors).length === 0;
  }

  async function submit(event) {
    event.preventDefault();
    if (!validateDetails()) return;
    setSaving(true);
    try {
      const pageFiles = [];
      for (const pageNumber of selectedPageNumbers) {
        const page = await pdfDocument.getPage(pageNumber);
        pageFiles.push({
          pageNumber,
          blob: await renderPdfPage(page, 3000, "image/png")
        });
      }
      const game = await createPdfGame({
        id: gameId,
        title: form.title.trim(),
        game_type: "pdf_deck",
        subtitle: form.subtitle.trim(),
        description: null,
        price: 0,
        sort_order: nextSortOrder,
        rules: form.rules.trim()
      }, coverFile, pdfFile, pageFiles);
      await onCreated(game);
    } catch (createError) {
      if (createError.message === "A game with this ID already exists.") {
        setGameId(buildGameId(form.title.trim()));
      } else {
        showToast(createError.message || "Unable to create the game.", "error");
      }
    } finally {
      setSaving(false);
    }
  }

  const orderedPreviewPages = [
    ...selectedPageNumbers
      .map((pageNumber) => pdfPages.find((page) => page.pageNumber === pageNumber))
      .filter(Boolean),
    ...pdfPages.filter((page) => !selectedPageNumbers.includes(page.pageNumber))
  ];

  return (
    <div className="modal-backdrop games-detail-backdrop">
      <div className="modal user-modal pdf-game-modal" role="dialog" aria-modal="true" aria-labelledby="add-game-title">
        <div className="modal-header">
          <div>
            <h3 id="add-game-title">{step === 1 ? "Add Game" : "Review Game"}</h3>
            <p className="muted">{step === 1 ? "Add information and upload the game content." : "Review the cover, rules, and card pages before creating."}</p>
          </div>
          <button type="button" className="icon-btn" onClick={onClose} disabled={saving} aria-label="Close Add Game"><X size={20} /></button>
        </div>
        <form className="pdf-game-form" onSubmit={submit} noValidate>
          <div className="modal-body pdf-game-modal-body">
            {step === 1 ? (
              <>
                <section className="pdf-game-step-section">
                  <h4>Step 1 — Game Information</h4>
                  <label htmlFor="new-game-title">Game Title</label>
                  <input id="new-game-title" value={form.title} onChange={(event) => update("title", event.target.value)} aria-invalid={Boolean(errors.title)} aria-describedby={errors.title ? "new-game-title-error" : undefined} required />
                  {errors.title && <span className="field-error" id="new-game-title-error">{errors.title}</span>}
                  <label htmlFor="new-game-subtitle">Subtitle <span className="muted">(optional)</span></label>
                  <input id="new-game-subtitle" value={form.subtitle} onChange={(event) => update("subtitle", event.target.value)} />
                  <label htmlFor="new-game-rules">Rules</label>
                  <textarea id="new-game-rules" rows={5} value={form.rules} onChange={(event) => update("rules", event.target.value)} aria-invalid={Boolean(errors.rules)} aria-describedby={errors.rules ? "new-game-rules-error" : undefined} required />
                  {errors.rules && <span className="field-error" id="new-game-rules-error">{errors.rules}</span>}
                </section>

                <section className="pdf-game-step-section">
                  <h4>Step 2 — Upload Game Cover</h4>
                  <div className="pdf-game-file-control">
                    <label className="pdf-game-upload" htmlFor="new-game-cover">
                      <ImagePlus size={18} />
                      <span>{coverFile ? `Replace Cover · ${coverFile.name}` : "Choose Game Cover Image"}</span>
                    </label>
                    <input id="new-game-cover" className="pdf-game-file-input" type="file" accept="image/jpeg,image/png,image/webp" onChange={chooseCover} disabled={saving} aria-invalid={Boolean(errors.cover)} aria-describedby={errors.cover ? "new-game-cover-error" : undefined} />
                  </div>
                  <span className="field-hint">JPEG, PNG, or WebP; maximum 10 MB. The image is kept at its original aspect ratio.</span>
                  {coverPreviewUrl && <img className="pdf-game-cover-preview" src={coverPreviewUrl} alt="Selected game cover preview" />}
                  {coverFile && <span className="field-hint">{coverFile.name}</span>}
                  {errors.cover && <span className="field-error" id="new-game-cover-error">{errors.cover}</span>}
                </section>

                <section className="pdf-game-step-section">
                  <h4>Step 3 — Upload Game Content PDF</h4>
                  <div className="pdf-game-file-control">
                    <label className="pdf-game-upload" htmlFor="new-game-pdf">
                      <FileText size={18} />
                      <span>{pdfFile ? `Replace PDF · ${pdfFile.name}` : "Choose Game Content PDF"}</span>
                    </label>
                    <input id="new-game-pdf" className="pdf-game-file-input" type="file" accept="application/pdf,.pdf" onChange={choosePdf} disabled={saving} aria-invalid={Boolean(errors.pdf)} aria-describedby={errors.pdf ? "new-game-pdf-error" : undefined} />
                  </div>
                  <span className="field-hint">PDF; maximum 50 MB. Each selected page becomes one complete card face.</span>
                  {pdfFile && <span className="field-hint">{pdfFile.name} · {pdfPages.length} {pdfPages.length === 1 ? "page" : "pages"}</span>}
                  {pdfLoading && <span className="field-hint">Rendering page {pdfProgress.current} of {pdfProgress.total}...</span>}
                  {errors.pdf && <span className="field-error" id="new-game-pdf-error">{errors.pdf}</span>}
                  {pdfPages.length > 0 && (
                    <>
                      <div className="pdf-page-heading">
                        <strong>Select card pages</strong>
                        <span>{selectedPageNumbers.length} selected</span>
                      </div>
                      <span className="field-hint">All pages are selected in their original PDF order. Deselect any page not needed.</span>
                      <div className="pdf-page-grid">
                        {orderedPreviewPages.map((page) => {
                          const selectedIndex = selectedPageNumbers.indexOf(page.pageNumber);
                          const selected = selectedIndex !== -1;
                          return (
                            <div className={`pdf-page-card${selected ? " selected" : ""}`} key={page.pageNumber}>
                              <img src={page.previewUrl} alt={`PDF page ${page.pageNumber} preview`} />
                              <div className="pdf-page-card-footer">
                                <label>
                                  <input type="checkbox" checked={selected} onChange={(event) => togglePdfPage(page.pageNumber, event.target.checked)} disabled={saving} />
                                  PDF page {page.pageNumber}
                                </label>
                                {selected && (
                                  <div className="pdf-page-order">
                                    <span>Card {selectedIndex + 1}</span>
                                    <button type="button" className="icon-btn" onClick={() => movePdfPage(page.pageNumber, -1)} disabled={saving || selectedIndex === 0} aria-label={`Move page ${page.pageNumber} earlier`}><ChevronUp size={16} /></button>
                                    <button type="button" className="icon-btn" onClick={() => movePdfPage(page.pageNumber, 1)} disabled={saving || selectedIndex === selectedPageNumbers.length - 1} aria-label={`Move page ${page.pageNumber} later`}><ChevronDown size={16} /></button>
                                  </div>
                                )}
                              </div>
                            </div>
                          );
                        })}
                      </div>
                    </>
                  )}
                  {errors.pages && <span className="field-error">{errors.pages}</span>}
                </section>
              </>
            ) : (
              <section className="pdf-game-review" aria-label="Review new game">
                <div className="pdf-game-review-heading">
                  {coverPreviewUrl && <img src={coverPreviewUrl} alt={`${form.title.trim()} cover`} />}
                  <div>
                    <h4>{form.title.trim()}</h4>
                    <span>{form.subtitle.trim() || "No subtitle"}</span>
                    <span>{selectedPageNumbers.length} {selectedPageNumbers.length === 1 ? "card" : "cards"}</span>
                  </div>
                </div>
                <div className="pdf-game-review-section">
                  <h4>Rules</h4>
                  <p>{form.rules.trim()}</p>
                </div>
                <div className="pdf-game-review-section">
                  <h4>Selected PDF Pages</h4>
                  <span className="field-hint">Source PDF: {pdfFile?.name}</span>
                  <div className="pdf-review-page-list">
                    {selectedPageNumbers.map((pageNumber, index) => {
                      const page = pdfPages.find((item) => item.pageNumber === pageNumber);
                      return page ? (
                        <div className="pdf-review-page" key={pageNumber}>
                          <img src={page.previewUrl} alt={`Card ${index + 1}, original PDF page ${pageNumber}`} />
                          <span>Card {index + 1} · PDF page {pageNumber}</span>
                        </div>
                      ) : null;
                    })}
                  </div>
                </div>
              </section>
            )}
          </div>
          <div className="modal-footer">
            {step === 2 && <button type="button" className="secondary-btn" onClick={() => setStep(1)} disabled={saving}>Back</button>}
            <button type="button" className="secondary-btn" onClick={onClose} disabled={saving}>Cancel</button>
            {step === 1 ? (
              <button type="button" className="primary-btn" onClick={() => {
                if (!validateDetails() || pdfLoading) return;
                setGameId(buildGameId(form.title.trim()));
                setStep(2);
              }} disabled={saving || pdfLoading}>
                {pdfLoading ? "Rendering PDF..." : "Review Game"}
              </button>
            ) : (
              <button type="submit" className="primary-btn" disabled={saving || pdfLoading}>
                {saving ? <><Loader2 size={17} className="spin" /> Creating...</> : "Create Game"}
              </button>
            )}
          </div>
        </form>
      </div>
    </div>
  );
}

function GameDetailsModal({ game, onClose, onSaved, showToast }) {
  const [details, setDetails] = useState({ rules: [], cards: [], placements: [] });
  const [loadErrors, setLoadErrors] = useState({});
  const [loading, setLoading] = useState(true);
  const [accessLoaded, setAccessLoaded] = useState(false);
  const [form, setForm] = useState({
    title: game.title || "",
    subtitle: game.subtitle || "",
    description: game.description || "",
    price: String(game.price ?? 0),
    sort_order: String(game.sort_order ?? 0),
    is_locked: Boolean(game.is_locked)
  });
  const [ruleDrafts, setRuleDrafts] = useState({});
  const [savingInfo, setSavingInfo] = useState(false);
  const [savingRuleId, setSavingRuleId] = useState(null);
  const [addRuleOpen, setAddRuleOpen] = useState(false);
  const [cardEditor, setCardEditor] = useState(null);
  const [cardPage, setCardPage] = useState(0);

  useEffect(() => {
    let active = true;
    setLoading(true);
    setAccessLoaded(false);
    setLoadErrors({});
    Promise.allSettled([
      loadGameDetails(game.id),
      loadGameAccess(game.id)
    ]).then(async ([detailsResult, accessResult]) => {
      const errors = {};
      let nextDetails = { rules: [], cards: [], placements: [] };

      if (detailsResult.status === "rejected") {
        errors.details = detailsResult.reason?.message || "Unable to load game details.";
      } else {
        const result = detailsResult.value;
        if (result.rules.error) errors.rules = result.rules.error.message;
        if (result.cards.error) errors.cards = result.cards.error.message;
        let placements = result.placements.data;
        if (result.placements.error) {
          errors.placements = result.placements.error.message;
          placements = [];
        } else {
          try {
            placements = await loadPlacementNames(placements);
          } catch (placementError) {
            errors.placements = placementError.message || "Unable to load placements.";
            placements = [];
          }
        }
        nextDetails = {
          rules: result.rules.data,
          cards: result.cards.data,
          placements
        };
      }

      if (!active) return;

      if (accessResult.status === "fulfilled" &&
          typeof accessResult.value?.is_locked === "boolean") {
        setForm((current) => ({
          ...current,
          is_locked: accessResult.value.is_locked
        }));
        setAccessLoaded(true);
      } else {
        const message = accessResult.status === "rejected"
          ? accessResult.reason?.message
          : "The game access setting was not returned.";
        errors.access = `Unable to load this game's access setting${message ? `: ${message}` : "."}`;
      }

      setLoadErrors(errors);
      setDetails(nextDetails);
      setRuleDrafts(Object.fromEntries(nextDetails.rules.map((rule) => [rule.id, rule.rule_text || ""])));
    }).finally(() => {
      if (active) setLoading(false);
    });

    return () => {
      active = false;
    };
  }, [game.id]);

  const cardPageCount = Math.ceil(details.cards.length / CARD_PAGE_SIZE);
  const visibleCards = details.cards.slice(cardPage * CARD_PAGE_SIZE, (cardPage + 1) * CARD_PAGE_SIZE);

  async function saveInformation(event) {
    event.preventDefault();
    const title = form.title.trim();
    const sortOrder = Number(form.sort_order);
    const price = Number(form.price);
    if (!title || !Number.isInteger(sortOrder) || !Number.isFinite(price) || price < 0) {
      showToast("Enter a title, a nonnegative price, and a whole-number sort order.", "error");
      return;
    }

    setSavingInfo(true);
    try {
      const updatedGame = await updateGameAccess(game.id, Boolean(form.is_locked), {
        title,
        subtitle: form.subtitle,
        description: form.description,
        sort_order: sortOrder,
        price
      });
      const accessChanged = Boolean(game.is_locked) !== Boolean(updatedGame.is_locked);
      await logAdminAction({
        action: accessChanged && title === game.title &&
          form.subtitle === (game.subtitle || "") &&
          form.description === (game.description || "") &&
          sortOrder === Number(game.sort_order) &&
          price === Number(game.price || 0)
          ? "game_access_changed"
          : "game_information_updated",
        targetType: "game",
        targetId: updatedGame.id,
        targetName: updatedGame.title,
        details: {
          changed_fields: [
            ...(title !== game.title ? ["title"] : []),
            ...(form.subtitle !== (game.subtitle || "") ? ["subtitle"] : []),
            ...(form.description !== (game.description || "") ? ["description"] : []),
            ...(sortOrder !== Number(game.sort_order) ? ["sort order"] : []),
            ...(price !== Number(game.price || 0) ? ["price"] : []),
            ...(accessChanged ? ["access"] : [])
          ],
          ...(accessChanged ? { access: updatedGame.is_locked ? "Locked" : "Free" } : {})
        }
      });
      onSaved(updatedGame);
      setForm({
        title: updatedGame.title || "",
        subtitle: updatedGame.subtitle || "",
        description: updatedGame.description || "",
        price: String(updatedGame.price ?? 0),
        sort_order: String(updatedGame.sort_order ?? 0),
        is_locked: Boolean(updatedGame.is_locked)
      });
      showToast(accessChanged
        ? `Game information and ${updatedGame.is_locked ? "locked" : "free"} access saved successfully.`
        : "Game information saved successfully.", "success");
    } catch (saveError) {
      showToast(saveError.message || "Unable to save game information.", "error");
    } finally {
      setSavingInfo(false);
    }
  }

  async function saveRule(rule) {
    setSavingRuleId(rule.id);
    try {
      await updateGameRule(rule.id, ruleDrafts[rule.id] || "");
      setDetails((current) => ({
        ...current,
        rules: current.rules.map((item) => item.id === rule.id
          ? { ...item, rule_text: ruleDrafts[rule.id] || "" }
          : item)
      }));
      const auditSucceeded = await logAdminAction({
        action: "game_rule_updated",
        targetType: "game",
        targetId: game.id,
        targetName: game.title,
        details: {
          rule_id: rule.id,
          sort_order: rule.sort_order,
          changed_fields: ["rule_text"]
        }
      }).catch((auditError) => {
        console.error("Game rule update audit logging failed.", {
          code: auditError?.code || auditError?.name || "AUDIT_LOG_FAILED"
        });
        return false;
      });
      showToast(
        auditSucceeded
          ? "Game rule saved successfully."
          : "Game rule saved, but its audit log could not be saved.",
        auditSucceeded ? "success" : "error"
      );
    } catch (saveError) {
      showToast(saveError.message || "Unable to save game rule.", "error");
    } finally {
      setSavingRuleId(null);
    }
  }

  async function createRule(ruleText) {
    let createdRule;
    try {
      createdRule = await createGameRule(game.id, ruleText);
    } catch (createError) {
      if (createError.message !== "A rule already exists for this game.") throw createError;

      try {
        const refreshed = await loadGameDetails(game.id);
        if (refreshed.rules.error) throw refreshed.rules.error;
        setDetails((current) => ({ ...current, rules: refreshed.rules.data }));
        setRuleDrafts(Object.fromEntries(
          refreshed.rules.data.map((rule) => [rule.id, rule.rule_text || ""])
        ));
        showToast("A rule already exists for this game.", "error");
      } catch (refreshError) {
        console.error("Existing game rule refresh failed.", {
          code: refreshError?.code || refreshError?.name || "UNKNOWN"
        });
        showToast("A rule already exists, but the rule list could not be refreshed.", "error");
      }
      setAddRuleOpen(false);
      return false;
    }

    setDetails((current) => ({
      ...current,
      rules: [...current.rules, createdRule]
    }));
    setRuleDrafts((current) => ({ ...current, [createdRule.id]: createdRule.rule_text || "" }));

    const auditSucceeded = await logAdminAction({
      action: "game_rule_created",
      targetType: "game",
      targetId: game.id,
      targetName: game.title,
      details: {
        rule_id: createdRule.id,
        sort_order: 1,
        created_fields: ["rule_text"]
      }
    }).catch((auditError) => {
      console.error("Game rule creation audit logging failed.", {
        code: auditError?.code || auditError?.name || "AUDIT_LOG_FAILED"
      });
      return false;
    });

    let refreshSucceeded = true;
    try {
      const refreshed = await loadGameDetails(game.id);
      if (refreshed.rules.error) throw refreshed.rules.error;
      setDetails((current) => ({ ...current, rules: refreshed.rules.data }));
      setRuleDrafts(Object.fromEntries(
        refreshed.rules.data.map((rule) => [rule.id, rule.rule_text || ""])
      ));
    } catch (refreshError) {
      refreshSucceeded = false;
      console.error("Game rules refresh failed after rule creation.", {
        code: refreshError?.code || refreshError?.name || "UNKNOWN"
      });
    }

    if (!auditSucceeded || !refreshSucceeded) {
      const issue = [
        !auditSucceeded && "its audit log could not be saved",
        !refreshSucceeded && "the rule list could not be refreshed"
      ].filter(Boolean).join(" and ");
      showToast(`Rule created, but ${issue}.`, "error");
    } else {
      showToast("Game rule added successfully.", "success");
    }
    return true;
  }

  async function refreshCards() {
    const refreshed = await loadGameDetails(game.id);
    if (refreshed.cards.error) throw refreshed.cards.error;
    setDetails((current) => ({ ...current, cards: refreshed.cards.data }));
    setCardPage((current) => {
      const lastPage = Math.max(0, Math.ceil(refreshed.cards.data.length / CARD_PAGE_SIZE) - 1);
      return Math.min(current, lastPage);
    });
    return refreshed.cards.data;
  }

  async function saveCard(card, form) {
    const sortOrder = card?.sort_order ??
      (details.cards.reduce((max, existingCard) => Math.max(max, existingCard.sort_order), 0) + 1);
    const payload = buildGameCardData(game, form, card, sortOrder);

    let savedCard;
    try {
      savedCard = card
        ? await updateGameCard(card.id, payload)
        : await createGameCard(game.id, payload);
    } catch (saveError) {
      if (!card && saveError.code === "23505") {
        try {
          await refreshCards();
          onSaved(game);
          showToast("Another card was added at the same time. The list was refreshed; please retry.", "error");
        } catch (refreshError) {
          console.error("Card list refresh failed after sort order conflict.", {
            code: refreshError?.code || refreshError?.name || "UNKNOWN"
          });
          showToast("Card order conflict. Refresh the game cards and try again.", "error");
        }
        return false;
      }
      showToast(saveError.message || "Unable to save the game card.", "error");
      return false;
    }

    let refreshSucceeded = true;
    try {
      const cards = await refreshCards();
      if (!card) setCardPage(Math.max(0, Math.ceil(cards.length / CARD_PAGE_SIZE) - 1));
    } catch (refreshError) {
      refreshSucceeded = false;
      console.error("Game card list refresh failed after save.", {
        code: refreshError?.code || refreshError?.name || "UNKNOWN"
      });
    }
    onSaved(game);

    const auditSucceeded = await logAdminAction({
      action: card ? "game_card_updated" : "game_card_created",
      targetType: "game",
      targetId: game.id,
      targetName: game.title,
      details: {
        card_id: savedCard.id,
        sort_order: savedCard.sort_order,
        changed_fields: [
          "front_text",
          "back_text",
          "metadata.pairs",
          "metadata.source_card",
          ...(game.game_type === "bible_question" ? ["metadata.category"] : [])
        ]
      }
    }).catch((auditError) => {
      console.error("Game card audit logging failed.", {
        action: card ? "game_card_updated" : "game_card_created",
        code: auditError?.code || auditError?.name || "AUDIT_LOG_FAILED"
      });
      return false;
    });

      if (!refreshSucceeded) {
        showToast(
          auditSucceeded
            ? "Card saved, but the card list could not be refreshed."
            : "Card saved, but the card list could not be refreshed and its audit log could not be saved.",
          "error"
        );
      } else {
        showToast(
          auditSucceeded
            ? card ? "Game card saved successfully." : "Game card added successfully."
            : card
              ? "Game card saved, but its audit log could not be saved."
              : "Game card added, but its audit log could not be saved.",
          auditSucceeded ? "success" : "error"
        );
      }
    return true;
  }

  return (
    <div className="modal-backdrop games-detail-backdrop">
      <div className="modal games-detail-modal game-edit-modal" role="dialog" aria-modal="true" aria-labelledby="game-detail-title">
        <div className="modal-header">
          <div><h3 id="game-detail-title">{game.title}</h3><p className="muted">Game details and content</p></div>
          <button type="button" className="icon-btn" onClick={onClose} aria-label="Close game details"><X size={20} /></button>
        </div>
        <div className="games-detail-body">
          {loadErrors.details && <div className="error-box">{loadErrors.details}</div>}
          {loadErrors.access && <div className="error-box">{loadErrors.access}</div>}

          <section className="games-detail-section">
            <h4>Game Information</h4>
            <form id="game-information-form" className="games-info-form" onSubmit={saveInformation}>
              <label>Title<input value={form.title} onChange={(event) => setForm((current) => ({ ...current, title: event.target.value }))} required /></label>
              <label>Subtitle<input value={form.subtitle} onChange={(event) => setForm((current) => ({ ...current, subtitle: event.target.value }))} /></label>
              <label>Description<textarea rows={3} value={form.description} onChange={(event) => setForm((current) => ({ ...current, description: event.target.value }))} /></label>
              <label>Price (₱)<input type="number" min="0" step="0.01" value={form.price} onChange={(event) => setForm((current) => ({ ...current, price: event.target.value }))} required /></label>
              <label>Sort Order<input type="number" step="1" value={form.sort_order} onChange={(event) => setForm((current) => ({ ...current, sort_order: event.target.value }))} required /></label>
              <div className="games-access-field">
                <span>Access</span>
                <div className="access-box games-access-box">
                  <div className="games-access-description">
                    <strong>Game access</strong>
                    <span className="muted">Locked games can be treated as restricted by your app.</span>
                  </div>
                  <label className="switch-row games-access-control">
                    <input
                      type="checkbox"
                      checked={Boolean(form.is_locked)}
                      onChange={(event) => setForm((current) => ({
                        ...current,
                        is_locked: event.target.checked
                      }))}
                      disabled={savingInfo || loading || !accessLoaded}
                    />
                    <span className="games-access-value">{form.is_locked ? "Locked" : "Free"}</span>
                  </label>
                </div>
              </div>
              <div className="games-readonly-fields">
                <div><span className="muted">Stable ID</span><code>{game.id}</code></div>
                <div><span className="muted">Game Type</span><code>{game.game_type}</code></div>
                <div><span className="muted">Access</span><span className={`status ${game.is_locked ? "locked" : "free"}`}>{game.is_locked ? "Locked" : "Free"}</span></div>
              </div>
              <div className="games-cover-detail">
                <span className="muted">Cover Image</span>
                {game.cover_display_url || game.cover_image_url ? <img src={game.cover_display_url || game.cover_image_url} alt={`${game.title} cover`} /> : <div className="cover-placeholder"><Gamepad2 size={22} /></div>}
                <span className="field-hint">{game.cover_image_url || "No cover image is configured."}</span>
              </div>
            </form>
          </section>

          <section className="games-detail-section">
            <h4>Placements</h4>
            {loadErrors.placements ? <div className="error-box">{loadErrors.placements}</div> : loading ? <p className="field-hint">Loading placements...</p> : details.placements.length === 0 ? <p className="field-hint">This game has no placements.</p> : (
              <ul className="games-placement-list">{details.placements.map((placement) => <li key={placement.id}>{placement.pillarName} <span aria-hidden="true">→</span> {placement.categoryName}</li>)}</ul>
            )}
          </section>

          <section className="games-detail-section">
            <h4>Rules</h4>
            {loadErrors.rules ? <div className="error-box">{loadErrors.rules}</div> : loading ? <p className="field-hint">Loading rules...</p> : details.rules.length === 0 ? (
              <div className="games-empty-rule">
                <p className="field-hint">No rule has been created for this game yet.</p>
                <button type="button" className="secondary-btn small" onClick={() => setAddRuleOpen(true)}>
                  <Plus size={15} /> Add Rule
                </button>
              </div>
            ) : details.rules.map((rule) => (
              <div className="games-rule-entry" key={rule.id}>
                <label>Rule {rule.sort_order}<textarea rows={5} value={ruleDrafts[rule.id] ?? ""} onChange={(event) => setRuleDrafts((current) => ({ ...current, [rule.id]: event.target.value }))} /></label>
                <details><summary>Structured metadata (read-only)</summary><pre>{formatMetadata(rule.metadata)}</pre></details>
                <div className="games-section-actions"><button type="button" className="secondary-btn small" onClick={() => saveRule(rule)} disabled={savingRuleId === rule.id}>{savingRuleId === rule.id ? "Saving..." : "Save Rule Text"}</button></div>
              </div>
            ))}
          </section>

          <section className="games-detail-section">
            <div className="games-cards-heading">
              <h4>Cards <span className="muted">({details.cards.length})</span></h4>
              <button type="button" className="secondary-btn small" onClick={() => setCardEditor({ card: null })} disabled={loading || Boolean(loadErrors.cards)}>
                <Plus size={15} /> Add Card
              </button>
              {details.cards.length > CARD_PAGE_SIZE && <div className="games-pagination"><button type="button" className="icon-btn" onClick={() => setCardPage((page) => Math.max(0, page - 1))} disabled={cardPage === 0} aria-label="Previous cards"><ChevronLeft size={18} /></button><span>{cardPage + 1} / {cardPageCount}</span><button type="button" className="icon-btn" onClick={() => setCardPage((page) => Math.min(cardPageCount - 1, page + 1))} disabled={cardPage >= cardPageCount - 1} aria-label="Next cards"><ChevronRight size={18} /></button></div>}
            </div>
            {loadErrors.cards ? <div className="error-box">{loadErrors.cards}</div> : loading ? <p className="field-hint">Loading cards...</p> : details.cards.length === 0 ? <p className="field-hint">No cards have been added for this game.</p> : visibleCards.map((card) => (
              <details className="games-card-entry" key={card.id}>
                <summary>Card {card.sort_order}</summary>
                <div className="games-card-fields">
                  <div><span className="muted">Front</span><p>{card.front_text || "—"}</p></div>
                  <div><span className="muted">Back</span><p>{card.back_text || "—"}</p></div>
                  <details><summary>Structured metadata (read-only)</summary><pre>{formatMetadata(card.metadata)}</pre></details>
                  <div className="games-section-actions">
                    <button type="button" className="secondary-btn small" onClick={() => setCardEditor({ card })}>
                      <Pencil size={14} /> Edit
                    </button>
                  </div>
                </div>
              </details>
            ))}
          </section>
        </div>
        <div className="modal-footer">
          <button type="button" className="secondary-btn" onClick={onClose} disabled={savingInfo}>Cancel</button>
          <button type="submit" form="game-information-form" className="primary-btn" disabled={savingInfo || loading || !accessLoaded}>
            {savingInfo ? "Saving..." : "Save Information"}
          </button>
        </div>
      </div>
      {addRuleOpen && (
        <AddGameRuleModal
          onClose={() => setAddRuleOpen(false)}
          onCreate={createRule}
          showToast={showToast}
        />
      )}
      {cardEditor && (
        <GameCardEditor
          game={game}
          card={cardEditor.card}
          onClose={() => setCardEditor(null)}
          onSave={saveCard}
          showToast={showToast}
        />
      )}
    </div>
  );
}

function GameCardEditor({ game, card, onClose, onSave, showToast }) {
  const [form, setForm] = useState(() => getCardEditorForm(game, card));
  const [errors, setErrors] = useState({});
  const [saving, setSaving] = useState(false);
  const fieldId = (field) => `game-card-${field.replace(/\./g, "-")}`;

  function setField(field, value) {
    setForm((current) => ({ ...current, [field]: value }));
    setErrors((current) => {
      if (!current[field]) return current;
      const next = { ...current };
      delete next[field];
      return next;
    });
  }

  function setArrayValue(field, index, value, key = null) {
    setForm((current) => ({
      ...current,
      [field]: current[field].map((item, itemIndex) => itemIndex !== index
        ? item
        : key ? { ...item, [key]: value } : value)
    }));
    const errorKey = key ? `${field}.${index}.${key}` : `${field}.${index}`;
    setErrors((current) => {
      if (!current[errorKey] && !current[field]) return current;
      const next = { ...current };
      delete next[errorKey];
      if (field === "entries" || field === "clues") delete next[field];
      return next;
    });
  }

  function addArrayValue(field, value) {
    setForm((current) => ({ ...current, [field]: [...current[field], value] }));
  }

  function removeArrayValue(field, index) {
    setForm((current) => ({
      ...current,
      [field]: current[field].filter((_, itemIndex) => itemIndex !== index)
    }));
    setErrors((current) => {
      const next = { ...current };
      delete next[field];
      return next;
    });
  }

  function input(label, field, value, multiline = false) {
    const id = fieldId(field);
    return (
      <>
        <label htmlFor={id}>{label}</label>
        {multiline
          ? <textarea id={id} rows={4} value={value} onChange={(event) => setField(field, event.target.value)} aria-invalid={Boolean(errors[field])} aria-describedby={errors[field] ? `${id}-error` : undefined} />
          : <input id={id} value={value} onChange={(event) => setField(field, event.target.value)} aria-invalid={Boolean(errors[field])} aria-describedby={errors[field] ? `${id}-error` : undefined} />}
        {errors[field] && <span className="field-error" id={`${id}-error`}>{errors[field]}</span>}
      </>
    );
  }

  function arrayInput(field, index, label, value, key = null, multiline = false) {
    const errorKey = key ? `${field}.${index}.${key}` : `${field}.${index}`;
    const id = fieldId(errorKey);
    return (
      <label className="game-card-field" htmlFor={id}>
        {label}
        {multiline
          ? <textarea id={id} rows={3} value={value} onChange={(event) => setArrayValue(field, index, event.target.value, key)} aria-invalid={Boolean(errors[errorKey])} aria-describedby={errors[errorKey] ? `${id}-error` : undefined} />
          : <input id={id} value={value} onChange={(event) => setArrayValue(field, index, event.target.value, key)} aria-invalid={Boolean(errors[errorKey])} aria-describedby={errors[errorKey] ? `${id}-error` : undefined} />}
        {errors[errorKey] && <span className="field-error" id={`${id}-error`}>{errors[errorKey]}</span>}
      </label>
    );
  }

  async function submit(event) {
    event.preventDefault();
    const nextErrors = validateGameCardForm(game.game_type, form);
    setErrors(nextErrors);
    if (Object.keys(nextErrors).length > 0) return;

    setSaving(true);
    try {
      const completed = await onSave(card, form);
      if (completed) onClose();
    } catch (saveError) {
      showToast(saveError.message || "Unable to save the game card.", "error");
    } finally {
      setSaving(false);
    }
  }

  function renderDynamicList(field, label, allowMultiline = false) {
    return (
      <div className="game-card-dynamic-list">
        <div className="game-card-list-heading"><strong>{label}</strong><button type="button" className="secondary-btn small" onClick={() => addArrayValue(field, "")} disabled={saving}>Add entry</button></div>
        {form[field].map((value, index) => (
          <div className="game-card-dynamic-row" key={`${field}-${index}`}>
            {arrayInput(field, index, `${label} ${index + 1}`, value, null, allowMultiline)}
            {form[field].length > 1 && <button type="button" className="secondary-btn small" onClick={() => removeArrayValue(field, index)} disabled={saving} aria-label={`Remove ${label.toLowerCase()} ${index + 1}`}>Remove</button>}
          </div>
        ))}
        {errors[field] && <span className="field-error">{errors[field]}</span>}
      </div>
    );
  }

  function renderFields() {
    switch (game.game_type) {
      case "bible_action":
        return form.pairs.map((pair, index) => (
          <div className="game-card-pair-fields" key={`pair-${index}`}>
            <strong>Pair {index + 1}</strong>
            {arrayInput("pairs", index, index === 0 ? "Target/action text (Left)" : "Left", pair.left, "left", true)}
            {arrayInput("pairs", index, index === 0 ? "Reference content (Right)" : "Right", pair.right, "right", true)}
          </div>
        ));
      case "bible_draw":
        return <>{input("Prompt/list label", "prompt", form.prompt, true)}{form.items.map((item, index) => arrayInput("items", index, `Drawing item ${index + 1}`, item, null, true))}</>;
      case "bible_groups":
        return <>{input("List/category heading", "heading", form.heading)}{renderDynamicList("entries", "List entry", true)}</>;
      case "bible_proverbs":
        return form.verses.map((verse, index) => (
          <div className="game-card-pair-fields" key={`verse-${index}`}>
            <strong>Verse {index + 1}</strong>
            {arrayInput("verses", index, "Verse text", verse.text, "text", true)}
            {arrayInput("verses", index, "Reference (optional)", verse.reference, "reference")}
            {arrayInput("verses", index, "Right text (optional)", verse.right, "right")}
            {arrayInput("verses", index, "Underlined/missing words (one per line)", verse.underlined, "underlined", true)}
          </div>
        ));
      case "bible_question":
        return <>{input("Category", "category", form.category)}{form.entries.map((entry, index) => arrayInput("entries", index, `Question/list entry ${index + 1}`, entry, null, true))}</>;
      case "bible_talk":
        return <>{input("Target word/topic", "target", form.target)}{renderDynamicList("clues", "Prohibited clue")}</>;
      case "inspirational_talk_1":
        return <>{input("Quote", "quote", form.quote, true)}{input("Author", "author", form.author)}{input("Question", "question", form.question, true)}</>;
      case "inspirational_talk_2":
        return <>{input("Quote", "quote", form.quote, true)}{input("Question", "question", form.question, true)}</>;
      default:
        return <span className="field-error">This game type does not support card editing.</span>;
    }
  }

  return (
    <div className="modal-backdrop games-detail-backdrop">
      <div className="modal user-modal game-card-editor-modal" role="dialog" aria-modal="true" aria-labelledby="game-card-editor-title">
        <div className="modal-header">
          <div>
            <h3 id="game-card-editor-title">{card ? "Edit Card" : "Add Card"}</h3>
            <p className="muted">{game.title} · {game.game_type}</p>
          </div>
          <button type="button" className="icon-btn" onClick={onClose} disabled={saving} aria-label="Close card editor"><X size={20} /></button>
        </div>
        <form onSubmit={submit} noValidate>
          <div className="modal-body game-card-editor-body">
            {errors.form && <div className="error-box">{errors.form}</div>}
            {renderFields()}
          </div>
          <div className="modal-footer">
            <button type="button" className="secondary-btn" onClick={onClose} disabled={saving}>Cancel</button>
            <button type="submit" className="primary-btn" disabled={saving}>
              {saving ? <><Loader2 size={17} className="spin" /> Saving...</> : card ? "Save Card" : "Add Card"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

function AddGameRuleModal({ onClose, onCreate, showToast }) {
  const [ruleText, setRuleText] = useState("");
  const [error, setError] = useState("");
  const [saving, setSaving] = useState(false);

  async function submit(event) {
    event.preventDefault();
    if (!ruleText.trim()) {
      setError("Rule text is required.");
      return;
    }

    setSaving(true);
    setError("");
    try {
      const created = await onCreate(ruleText);
      if (created) onClose();
    } catch (createError) {
      if (createError.message === "A rule already exists for this game.") {
        setError(createError.message);
      } else {
        showToast(createError.message || "Unable to create the game rule.", "error");
      }
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="modal-backdrop games-detail-backdrop">
      <div className="modal user-modal" role="dialog" aria-modal="true" aria-labelledby="add-game-rule-title">
        <div className="modal-header">
          <div><h3 id="add-game-rule-title">Add Rule</h3><p className="muted">Create the game’s first rule.</p></div>
          <button type="button" className="icon-btn" onClick={onClose} disabled={saving} aria-label="Close Add Rule"><X size={20} /></button>
        </div>
        <form onSubmit={submit} noValidate>
          <div className="modal-body">
            <label htmlFor="new-game-rule-text">Rule Text</label>
            <textarea
              id="new-game-rule-text"
              rows={8}
              value={ruleText}
              onChange={(event) => {
                setRuleText(event.target.value);
                if (error === "Rule text is required.") setError("");
              }}
              aria-invalid={Boolean(error)}
              aria-describedby={error ? "new-game-rule-error" : undefined}
              required
            />
            {error && <span className="field-error" id="new-game-rule-error">{error}</span>}
          </div>
          <div className="modal-footer">
            <button type="button" className="secondary-btn" onClick={onClose} disabled={saving}>Cancel</button>
            <button type="submit" className="primary-btn" disabled={saving}>
              {saving ? <><Loader2 size={17} className="spin" /> Saving...</> : "Add Rule"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
