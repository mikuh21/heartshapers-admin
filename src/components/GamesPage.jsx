import React, { useEffect, useMemo, useState } from "react";
import {
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  Eye,
  Gamepad2,
  Loader2,
  Pencil,
  Plus,
  Search,
  X
} from "lucide-react";
import { logAdminAction } from "../lib/adminAudit";
import {
  createGame,
  createGameCard,
  createGameRule,
  listGamesWithCounts,
  loadGameDetails,
  loadPlacementNames,
  updateGameInformation,
  updateGameCard,
  updateGameRule,
  updateGameStatus
} from "../lib/games";

const CARD_PAGE_SIZE = 20;
const GAME_TYPES = [
  { label: "Bible Action", value: "bible_action" },
  { label: "Bible Draw", value: "bible_draw" },
  { label: "Bible Groups", value: "bible_groups" },
  { label: "Bible Proverbs", value: "bible_proverbs" },
  { label: "Bible Question", value: "bible_question" },
  { label: "Bible Talk", value: "bible_talk" },
  { label: "Inspirational Talk 1", value: "inspirational_talk_1" },
  { label: "Inspirational Talk 2", value: "inspirational_talk_2" }
];

function StatusBadge({ active }) {
  return <span className={`status ${active ? "active" : "disabled"}`}>{active ? "Active" : "Inactive"}</span>;
}

function formatMetadata(metadata) {
  return JSON.stringify(metadata ?? {}, null, 2);
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
  const [statusFilter, setStatusFilter] = useState("all");
  const [pillarFilter, setPillarFilter] = useState("all");
  const [selectedGame, setSelectedGame] = useState(null);
  const [addGameOpen, setAddGameOpen] = useState(false);
  const [statusTarget, setStatusTarget] = useState(null);
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
      const matchesStatus = statusFilter === "all" ||
        game.is_active === (statusFilter === "active");
      const matchesPillar = pillarFilter === "all" ||
        game.pillarIds.includes(pillarFilter);
      return matchesSearch && matchesStatus && matchesPillar;
    });
  }, [games, search, statusFilter, pillarFilter]);

  async function confirmStatusChange() {
    const target = statusTarget;
    if (!target) return;
    const updatedGame = await updateGameStatus(target.id, !target.is_active);
    setGames((current) => current.map((game) => game.id === updatedGame.id
      ? { ...game, ...updatedGame }
      : game));
    setSelectedGame((current) => current?.id === updatedGame.id
      ? { ...current, ...updatedGame }
      : current);
    await logAdminAction({
      action: "game_status_changed",
      targetType: "game",
      targetId: updatedGame.id,
      targetName: updatedGame.title,
      details: { status: updatedGame.is_active ? "Activated" : "Deactivated" }
    });
    showToast(`${updatedGame.title} ${updatedGame.is_active ? "activated" : "deactivated"} successfully.`, "success");
    return true;
  }

  if (!canManageGames) {
    return <div className="settings-card access-card"><h3>Access denied</h3><p className="muted">You do not have permission to manage games.</p></div>;
  }

  return (
    <>
      <div className="page-heading">
        <div>
          <h3>Games</h3>
          <p className="muted">Manage game information and review rules, cards, and placements.</p>
        </div>
        <button type="button" className="primary-btn" onClick={() => setAddGameOpen(true)}>
          <Plus size={18} /> Add Game
        </button>
      </div>

      <div className="toolbar games-toolbar">
        <div className="search-box">
          <Search size={18} />
          <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search games or types..." />
        </div>
        <div className="select-box">
          <select value={statusFilter} onChange={(event) => setStatusFilter(event.target.value)} aria-label="Filter games by status">
            <option value="all">All statuses</option>
            <option value="active">Active</option>
            <option value="inactive">Inactive</option>
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
              <thead><tr><th>Game</th><th>Game Type</th><th>Cards</th><th>Status</th><th>Placements</th><th>Actions</th></tr></thead>
              <tbody>
                {filteredGames.map((game) => (
                  <tr key={game.id}>
                    <td><div className="games-name-cell">{game.cover_image_url ? <img src={game.cover_image_url} alt="" /> : <div className="cover-placeholder"><Gamepad2 size={20} /></div>}<div><strong>{game.title}</strong><span>{game.subtitle || game.id}</span></div></div></td>
                    <td><code>{game.game_type}</code></td>
                    <td>{game.cardCount}</td>
                    <td><StatusBadge active={game.is_active} /></td>
                    <td>{game.placementCount}</td>
                    <td><div className="games-actions">
                      <button type="button" className="secondary-btn small" onClick={() => setSelectedGame(game)}><Eye size={15} /> View / Edit</button>
                      <button type="button" className={`secondary-btn small ${game.is_active ? "danger" : ""}`} onClick={() => setStatusTarget(game)}>{game.is_active ? "Deactivate" : "Activate"}</button>
                    </div></td>
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
                "Game Type": GAME_TYPES.find((type) => type.value === game.game_type)?.label || game.game_type,
                ...(game.subtitle ? { Subtitle: game.subtitle } : {}),
                ...(game.description ? { Description: game.description } : {}),
                "Sort Order": game.sort_order,
                "Initial Status": "Inactive"
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
                ? `${game.title} created as inactive.`
                : "Game created as inactive, but its audit log could not be saved.",
              auditSucceeded ? "success" : "error"
            );
          }}
          nextSortOrder={games.reduce((max, game) => Math.max(max, Number(game.sort_order) || 0), 0) + 1}
          showToast={showToast}
        />
      )}
      {statusTarget && (
        <ConfirmModal
          title={statusTarget.is_active ? "Deactivate Game?" : "Activate Game?"}
          message={statusTarget.is_active
            ? `Are you sure you want to deactivate ${statusTarget.title}? Deactivated games will no longer be available to the mobile application.`
            : `Are you sure you want to activate ${statusTarget.title}?`}
          actionLabel={statusTarget.is_active ? "Deactivate" : "Activate"}
          busyLabel={statusTarget.is_active ? "Deactivating..." : "Activating..."}
          tone={statusTarget.is_active ? "danger" : "success"}
          onClose={() => setStatusTarget(null)}
          onConfirm={confirmStatusChange}
        />
      )}
    </>
  );
}

function AddGameModal({ existingGames, nextSortOrder, onClose, onCreated, showToast }) {
  const [form, setForm] = useState({
    id: "",
    title: "",
    game_type: "",
    subtitle: "",
    description: "",
    sort_order: String(nextSortOrder)
  });
  const [errors, setErrors] = useState({});
  const [saving, setSaving] = useState(false);

  function update(field, value) {
    setForm((current) => ({ ...current, [field]: value }));
    setErrors((current) => {
      if (!current[field]) return current;
      const next = { ...current };
      delete next[field];
      return next;
    });
  }

  async function submit(event) {
    event.preventDefault();
    const nextErrors = {};
    const id = form.id.trim();
    const title = form.title.trim();
    const sortOrderText = form.sort_order.trim();
    const sortOrder = sortOrderText === "" ? nextSortOrder : Number(sortOrderText);

    if (!id) nextErrors.id = "Game ID is required.";
    else if (!/^[a-z0-9_-]+$/.test(id)) {
      nextErrors.id = "Use lowercase letters, numbers, hyphens, or underscores only.";
    } else if (existingGames.some((game) => game.id === id)) {
      nextErrors.id = "A game with this ID already exists.";
    }
    if (!title) nextErrors.title = "Game title is required.";
    if (!GAME_TYPES.some((type) => type.value === form.game_type)) {
      nextErrors.game_type = "Select a supported game type.";
    }
    if (sortOrderText !== "" && (!Number.isFinite(sortOrder) || !Number.isInteger(sortOrder))) {
      nextErrors.sort_order = "Sort order must be a whole number.";
    }

    setErrors(nextErrors);
    if (Object.keys(nextErrors).length > 0) return;

    setSaving(true);
    try {
      const game = await createGame({
        id,
        title,
        game_type: form.game_type,
        subtitle: form.subtitle.trim(),
        description: form.description.trim(),
        sort_order: sortOrder
      });
      await onCreated(game);
    } catch (createError) {
      if (createError.message === "A game with this ID already exists.") {
        setErrors((current) => ({ ...current, id: createError.message }));
      } else {
        showToast(createError.message || "Unable to create the game.", "error");
      }
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="modal-backdrop games-detail-backdrop">
      <div className="modal user-modal" role="dialog" aria-modal="true" aria-labelledby="add-game-title">
        <div className="modal-header">
          <div><h3 id="add-game-title">Add Game</h3><p className="muted">New games are created inactive.</p></div>
          <button type="button" className="icon-btn" onClick={onClose} disabled={saving} aria-label="Close Add Game"><X size={20} /></button>
        </div>
        <form onSubmit={submit} noValidate>
          <div className="modal-body">
            <label htmlFor="new-game-id">Game ID</label>
            <input id="new-game-id" value={form.id} onChange={(event) => update("id", event.target.value)} aria-invalid={Boolean(errors.id)} aria-describedby={errors.id ? "new-game-id-error" : undefined} required />
            {errors.id && <span className="field-error" id="new-game-id-error">{errors.id}</span>}
            <span className="field-hint">Use a stable lowercase ID, for example game-bible-charades.</span>

            <label htmlFor="new-game-title">Title</label>
            <input id="new-game-title" value={form.title} onChange={(event) => update("title", event.target.value)} aria-invalid={Boolean(errors.title)} aria-describedby={errors.title ? "new-game-title-error" : undefined} required />
            {errors.title && <span className="field-error" id="new-game-title-error">{errors.title}</span>}

            <label htmlFor="new-game-type">Game Type</label>
            <select id="new-game-type" value={form.game_type} onChange={(event) => update("game_type", event.target.value)} aria-invalid={Boolean(errors.game_type)} aria-describedby={errors.game_type ? "new-game-type-error" : undefined} required>
              <option value="">Select a game type</option>
              {GAME_TYPES.map((type) => <option key={type.value} value={type.value}>{type.label} — {type.value}</option>)}
            </select>
            {errors.game_type && <span className="field-error" id="new-game-type-error">{errors.game_type}</span>}

            <label htmlFor="new-game-subtitle">Subtitle <span className="muted">(optional)</span></label>
            <input id="new-game-subtitle" value={form.subtitle} onChange={(event) => update("subtitle", event.target.value)} />

            <label htmlFor="new-game-description">Description <span className="muted">(optional)</span></label>
            <textarea id="new-game-description" rows={3} value={form.description} onChange={(event) => update("description", event.target.value)} />

            <label htmlFor="new-game-sort-order">Sort Order <span className="muted">(optional)</span></label>
            <input id="new-game-sort-order" type="number" step="1" value={form.sort_order} onChange={(event) => update("sort_order", event.target.value)} aria-invalid={Boolean(errors.sort_order)} aria-describedby={errors.sort_order ? "new-game-sort-order-error" : undefined} />
            {errors.sort_order && <span className="field-error" id="new-game-sort-order-error">{errors.sort_order}</span>}
          </div>
          <div className="modal-footer">
            <button type="button" className="secondary-btn" onClick={onClose} disabled={saving}>Cancel</button>
            <button type="submit" className="primary-btn" disabled={saving}>
              {saving ? <><Loader2 size={17} className="spin" /> Creating...</> : "Create Game"}
            </button>
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
  const [form, setForm] = useState({
    title: game.title || "",
    subtitle: game.subtitle || "",
    description: game.description || "",
    sort_order: String(game.sort_order ?? 0)
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
    loadGameDetails(game.id).then(async (result) => {
      const errors = {};
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
      if (!active) return;
      setLoadErrors(errors);
      setDetails({
        rules: result.rules.data,
        cards: result.cards.data,
        placements
      });
      setRuleDrafts(Object.fromEntries(result.rules.data.map((rule) => [rule.id, rule.rule_text || ""])));
    }).catch((loadError) => {
      if (active) setLoadErrors({ details: loadError.message || "Unable to load game details." });
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
    if (!title || !Number.isInteger(sortOrder)) {
      showToast("Enter a title and a whole-number sort order.", "error");
      return;
    }

    setSavingInfo(true);
    try {
      const updatedGame = await updateGameInformation(game.id, {
        ...form,
        title,
        sort_order: sortOrder
      });
      await logAdminAction({
        action: "game_information_updated",
        targetType: "game",
        targetId: updatedGame.id,
        targetName: updatedGame.title,
        details: { changed_fields: ["title", "subtitle", "description", "sort order"] }
      });
      onSaved(updatedGame);
      setForm({
        title: updatedGame.title || "",
        subtitle: updatedGame.subtitle || "",
        description: updatedGame.description || "",
        sort_order: String(updatedGame.sort_order ?? 0)
      });
      showToast("Game information saved successfully.", "success");
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
      <div className="modal games-detail-modal" role="dialog" aria-modal="true" aria-labelledby="game-detail-title">
        <div className="modal-header">
          <div><h3 id="game-detail-title">{game.title}</h3><p className="muted">Game details and content</p></div>
          <button type="button" className="icon-btn" onClick={onClose} aria-label="Close game details"><X size={20} /></button>
        </div>
        <div className="games-detail-body">
          {loadErrors.details && <div className="error-box">{loadErrors.details}</div>}

          <section className="games-detail-section">
            <h4>Game Information</h4>
            <form className="games-info-form" onSubmit={saveInformation}>
              <label>Title<input value={form.title} onChange={(event) => setForm((current) => ({ ...current, title: event.target.value }))} required /></label>
              <label>Subtitle<input value={form.subtitle} onChange={(event) => setForm((current) => ({ ...current, subtitle: event.target.value }))} /></label>
              <label>Description<textarea rows={3} value={form.description} onChange={(event) => setForm((current) => ({ ...current, description: event.target.value }))} /></label>
              <label>Sort Order<input type="number" step="1" value={form.sort_order} onChange={(event) => setForm((current) => ({ ...current, sort_order: event.target.value }))} required /></label>
              <div className="games-readonly-fields">
                <div><span className="muted">Stable ID</span><code>{game.id}</code></div>
                <div><span className="muted">Game Type</span><code>{game.game_type}</code></div>
                <div><span className="muted">Status</span><StatusBadge active={game.is_active} /></div>
              </div>
              <div className="games-cover-detail">
                <span className="muted">Cover Image</span>
                {game.cover_image_url ? <img src={game.cover_image_url} alt={`${game.title} cover`} /> : <div className="cover-placeholder"><Gamepad2 size={22} /></div>}
                <span className="field-hint">{game.cover_image_url || "No cover image is configured."}</span>
              </div>
              <div className="games-section-actions"><button type="submit" className="primary-btn" disabled={savingInfo}>{savingInfo ? "Saving..." : "Save Information"}</button></div>
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
        <div className="modal-footer"><button type="button" className="secondary-btn" onClick={onClose}>Close</button></div>
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
