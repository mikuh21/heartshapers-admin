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
import { getLegacyGameRuleBlocks, parseInlineFormatting } from "../lib/legacyGameRuleBlocks";
import {
  createPdfGame,
  downloadPdfGameSource,
  deleteGame,
  loadGameAccess,
  listGamesWithCounts,
  loadGameDetails,
  updateGameAccess,
  updateGameWithCover,
  updatePdfGame
} from "../lib/games";
import { gameUploadSizeError, loadGameUploadLimit } from "../lib/uploadSettings";
import { supabase } from "../lib/supabase";

const CARD_PAGE_SIZE = 20;

const GAME_COVER_OPTIMIZATION_KEY = "game_cover_optimization_v1";

async function loadGameCoverOptimizationState() {
  const { data, error } = await supabase
    .from("app_settings")
    .select("value")
    .eq("key", GAME_COVER_OPTIMIZATION_KEY)
    .maybeSingle();
  if (error) throw error;
  const value = data?.value;
  return value && typeof value === "object" && Array.isArray(value.attemptedGameIds)
    ? value
    : { version: 1, attemptedGameIds: [], optimized: 0, skipped: 0, failed: 0 };
}

async function saveGameCoverOptimizationState(state) {
  const { data: sessionData } = await supabase.auth.getSession();
  const { error } = await supabase
    .from("app_settings")
    .upsert({
      key: GAME_COVER_OPTIMIZATION_KEY,
      value: state,
      updated_at: new Date().toISOString(),
      updated_by: sessionData?.session?.user?.id || null
    }, { onConflict: "key" });
  if (error) throw error;
}

async function optimizeExistingGameCover(url) {
  if (!url || typeof createImageBitmap !== "function" || typeof document === "undefined") {
    throw new Error("This browser does not support cover optimization.");
  }
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Unable to download cover (HTTP ${response.status}).`);
  const sourceBlob = await response.blob();
  if (!sourceBlob.type.startsWith("image/")) throw new Error("The cover URL did not return an image.");
  let bitmap;
  try {
    bitmap = await createImageBitmap(sourceBlob);
    const maxDimension = 1200;
    const scale = Math.min(1, maxDimension / Math.max(bitmap.width, bitmap.height));
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(bitmap.width * scale));
    canvas.height = Math.max(1, Math.round(bitmap.height * scale));
    const context = canvas.getContext("2d");
    if (!context) throw new Error("Unable to initialize the image optimizer.");
    context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/webp", 0.78));
    if (!blob) throw new Error("The browser could not encode the optimized cover.");
    return blob.size < sourceBlob.size * 0.9 ? blob : null;
  } finally {
    bitmap?.close?.();
  }
}

function ConfirmingForm({ children, onConfirm, ConfirmModal, title, message, actionLabel = "Save Changes", shouldConfirm = true, ...formProps }) {
  const [open, setOpen] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  async function confirm() {
    if (submitting) return;
    setSubmitting(true);
    try {
      await onConfirm({ preventDefault() {} });
      setOpen(false);
    } finally {
      setSubmitting(false);
    }
  }
  return (
    <>
      <form {...formProps} onSubmit={(event) => {
        event.preventDefault();
        if (!shouldConfirm) {
          onConfirm(event);
          return;
        }
        if (!submitting) setOpen(true);
      }}>
        {children}
      </form>
      {open && <ConfirmModal title={title} message={message} actionLabel={actionLabel} busyLabel="Saving..." tone="primary" icon={AlertTriangle} onClose={() => { if (!submitting) setOpen(false); }} onConfirm={confirm} />}
    </>
  );
}


const LEGACY_METADATA_GAME_TYPES = new Set([
  "bible_action",
  "bible_draw",
  "bible_groups",
  "bible_proverbs",
  "bible_question",
  "bible_talk",
  "inspirational_talk_1",
  "inspirational_talk_2"
]);

function getGameDescription(game, rules = []) {
  if (typeof game.description === "string") return game.description;
  if (!LEGACY_METADATA_GAME_TYPES.has(game.game_type)) return "";
  const hasLegacySubtitleMetadata = rules.some((rule) => (
    typeof rule.metadata?.source_rule?.heading === "string"
    && rule.metadata.source_rule.heading.trim()
  ));
  return game.subtitle?.trim().toLocaleLowerCase() === "card game" && hasLegacySubtitleMetadata
    ? game.subtitle
    : "";
}

function getLegacyGameSubtitle(game, rules = []) {
  const storedSubtitle = typeof game.subtitle === "string" ? game.subtitle : "";
  if (!LEGACY_METADATA_GAME_TYPES.has(game.game_type)) return storedSubtitle.trim() ? storedSubtitle : "";
  if (!storedSubtitle.trim()) return "";
  if (storedSubtitle.trim().toLocaleLowerCase() !== "card game") return storedSubtitle;

  const metadataSubtitle = rules
    .map((rule) => rule.metadata?.source_rule?.heading)
    .find((heading) => typeof heading === "string" && heading.trim());
  return typeof metadataSubtitle === "string" ? metadataSubtitle : storedSubtitle;
}

function getRuleMetadata(rule) {
  const metadata = rule.metadata && typeof rule.metadata === "object" && !Array.isArray(rule.metadata)
    ? rule.metadata
    : {};
  const effective = metadata.screen_effective_rule;
  const source = metadata.source_rule;

  if (effective && typeof effective === "object" && Array.isArray(effective.rules) && effective.rules.length > 0) {
    return {
      rules: effective.rules
    };
  }

  if (source && typeof source === "object" && Array.isArray(source.rules) && source.rules.length > 0) {
    return {
      rules: source.rules
    };
  }

  return null;
}

function isRuleSectionHeading(item) {
  const text = typeof item === "string" ? item.trim() : "";
  return Boolean(text && /[A-Z]/.test(text) && text === text.toLocaleUpperCase() && text.length <= 60);
}

function getRuleSections(rules) {
  const sections = [];
  let currentSection = null;

  for (const item of rules) {
    if (item && typeof item === "object" && !Array.isArray(item)
      && (item.type === "heading" || item.type === "section")) {
      currentSection = {
        heading: typeof item.text === "string" ? item.text : "",
        items: []
      };
      sections.push(currentSection);
      continue;
    }

    const structuredItems = !Array.isArray(item) && item && typeof item === "object"
      ? (Array.isArray(item.rules) ? item.rules : Array.isArray(item.items) ? item.items : null)
      : null;
    const structuredHeading = structuredItems
      ? (typeof item.heading === "string" ? item.heading : typeof item.title === "string" ? item.title : "")
      : "";

    if (structuredItems) {
      currentSection = { heading: structuredHeading, items: structuredItems };
      sections.push(currentSection);
      continue;
    }

    if (isRuleSectionHeading(item)) {
      currentSection = { heading: item.trim(), items: [] };
      sections.push(currentSection);
    } else {
      if (!currentSection) {
        currentSection = { heading: "", items: [] };
        sections.push(currentSection);
      }
      currentSection.items.push(item);
    }
  }

  return sections;
}

function parseRuleText(ruleText) {
  const blocks = [];
  const listStack = [];
  let paragraphLines = [];

  function flushParagraph() {
    if (paragraphLines.length > 0) {
      blocks.push({ type: "paragraph", lines: paragraphLines });
      paragraphLines = [];
    }
  }

  for (const line of String(ruleText ?? "").split(/\r\n?|\n/)) {
    const match = line.match(/^(\s*)(?:(\d+)[.)]|([-*•]))[ \t]+(.*)$/u);
    if (!match) {
      listStack.length = 0;
      if (!line.trim()) {
        flushParagraph();
      } else {
        paragraphLines.push(line);
      }
      continue;
    }

    flushParagraph();
    const indent = match[1].replace(/\t/g, "  ").length;
    const type = match[2] ? "ordered" : "unordered";
    const item = { text: match[4], number: match[2] ? Number(match[2]) : null, children: [] };
    while (listStack.length > 0 && listStack[listStack.length - 1].indent > indent) listStack.pop();
    let parent = listStack[listStack.length - 1];
    if (parent?.indent === indent) {
      if (parent.type === type) {
        parent.items.push(item);
        continue;
      }
      listStack.pop();
      parent = listStack[listStack.length - 1];
    }

    const list = {
      type,
      indent,
      items: [],
      parentItem: parent?.items[parent.items.length - 1] || null
    };
    if (parent && indent > parent.indent && list.parentItem) {
      list.parentItem.children.push(list);
    } else {
      blocks.push({ type: "list", list });
    }
    list.items.push(item);
    listStack.push(list);
  }
  flushParagraph();
  return blocks;
}

function RuleList({ list }) {
  const ListTag = list.type === "ordered" ? "ol" : "ul";
  const start = list.type === "ordered"
    ? list.start ?? (list.items[0]?.number > 1 ? list.items[0].number : undefined)
    : undefined;
  return (
    <ListTag start={start}>
      {list.items.map((item, index) => (
        <li key={`${item.number ?? "bullet"}-${index}`}>
          <RuleItemContent item={item} />
          {(item.children ?? []).map((child, childIndex) => (
            <RuleList key={`${child.type}-${childIndex}`} list={child} />
          ))}
        </li>
      ))}
    </ListTag>
  );
}

function InlineFormattedText({ text }) {
  return parseInlineFormatting(text).map((segment, index) => {
    if (segment.type === "underline") {
      return <u key={index}>{segment.text}</u>;
    }
    if (segment.type === "bold") {
      return <strong key={index}>{segment.text}</strong>;
    }
    return segment.text;
  });
}

function getRuleChildren(item) {
  if (!item || typeof item !== "object" || Array.isArray(item)) return [];
  for (const key of ["children", "subitems", "subItems", "sub_items", "subrules", "subRules", "sub_rules", "bullets", "items"]) {
    if (Array.isArray(item[key])) return item[key];
  }
  return [];
}

function RuleItem({ item }) {
  const children = getRuleChildren(item);
  return (
    <li>
      <RuleItemContent item={item} />
      {children.length > 0 && (
        <ul>
          {children.map((child, index) => <RuleItem key={index} item={child} />)}
        </ul>
      )}
    </li>
  );
}

function RuleItemContent({ item }) {
  if (typeof item === "string") return <InlineFormattedText text={item} />;
  if (!item || typeof item !== "object" || Array.isArray(item)) return null;

  if (Array.isArray(item.parts)) {
    return item.parts.map((part, index) => (
      part.bold
        ? <strong key={index}>{part.text}</strong>
        : <InlineFormattedText key={index} text={part.text} />
    ));
  }

  if (item.type === "heading" || item.type === "section") {
    return typeof item.text === "string" ? <InlineFormattedText text={item.text} /> : null;
  }

  if ("prefix" in item || "bold" in item || "suffix" in item) {
    return (
      <>
        {typeof item.prefix === "string" ? item.prefix : ""}
        {typeof item.bold === "string" && item.bold ? <strong>{item.bold}</strong> : null}
        {typeof item.suffix === "string" ? item.suffix : ""}
      </>
    );
  }

  return typeof item.text === "string" ? <InlineFormattedText text={item.text} /> : null;
}

function FormattedRule({ rule, gameType }) {
  const metadata = getRuleMetadata(rule);
  if (metadata) {
    const legacyBlocks = getLegacyGameRuleBlocks(gameType, rule.metadata?.source_rule);
    const sections = getRuleSections(metadata.rules);
    return (
      <div className="games-rule-entry">
        <div className="games-rule-content">
          {legacyBlocks
            ? legacyBlocks.map((block, index) => block.type === "list"
              ? <RuleList key={index} list={block.list} />
              : <p className="games-rule-paragraph" key={index}><RuleItemContent item={block.item} /></p>)
            : sections.map((section, sectionIndex) => {
            const explicitSection = Boolean(section.heading);
            const displayAsBullets = explicitSection && /\bRULES$/i.test(section.heading);
            const hasRuleHierarchy = section.items.some((item) => getRuleChildren(item).length > 0);
            const ListTag = displayAsBullets ? "ul" : "ol";

            return (
              <section className="games-rule-group" key={sectionIndex}>
                {section.heading && <h6><InlineFormattedText text={section.heading} /></h6>}
                {section.items.length > 0 && (
                  explicitSection && !displayAsBullets && !hasRuleHierarchy
                    ? section.items.map((item, itemIndex) => (
                      <p className="games-rule-paragraph" key={itemIndex}><RuleItemContent item={item} /></p>
                    ))
                    : <ListTag>
                      {section.items.map((item, itemIndex) => <RuleItem key={itemIndex} item={item} />)}
                    </ListTag>
                )}
              </section>
            );
          })}
        </div>
      </div>
    );
  }

  const blocks = parseRuleText(rule.rule_text);
  return (
    <div className="games-rule-entry">
      <strong>Rule {rule.sort_order}</strong>
      <div className="games-rule-content">
        {blocks.map((block, index) => block.type === "list"
          ? <RuleList key={index} list={block.list} />
          : <p key={index}><InlineFormattedText text={block.lines.join("\n")} /></p>)}
      </div>
    </div>
  );
}

function GameCoverFrame({ src, className = "" }) {
  const [failed, setFailed] = useState(false);
  const [aspectRatio, setAspectRatio] = useState(null);

  useEffect(() => {
    setFailed(false);
    setAspectRatio(null);
  }, [src]);

  const hasCover = Boolean(src) && !failed;

  return (
    <span
      className={`games-cover-frame${className ? ` ${className}` : ""}${hasCover ? " has-cover" : " is-placeholder"}`}
      style={hasCover ? { aspectRatio: aspectRatio ?? "16 / 9" } : undefined}
      aria-hidden="true"
    >
      {hasCover
        ? <img
            src={src}
            alt=""
            onLoad={(event) => {
              const { naturalWidth, naturalHeight } = event.currentTarget;
              if (naturalWidth > 0 && naturalHeight > 0) {
                setAspectRatio(naturalWidth / naturalHeight);
              }
            }}
            onError={() => setFailed(true)}
          />
        : <Gamepad2 size={19} />}
    </span>
  );
}

function GameTableCover({ src }) {
  return <GameCoverFrame src={src} />;
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
  const [editingPdfGame, setEditingPdfGame] = useState(null);
  const [accessGame, setAccessGame] = useState(null);
  const [deleteTarget, setDeleteTarget] = useState(null);
  const [refreshKey, setRefreshKey] = useState(0);
  const [gameUploadLimit, setGameUploadLimit] = useState(null);
  const [uploadLimitError, setUploadLimitError] = useState("");
  const gameCoverOptimizationStartedRef = useRef(false);
  const [gameCoverOptimizationProgress, setGameCoverOptimizationProgress] = useState(null);

  useEffect(() => {
    if (!addGameOpen && !editingPdfGame && !selectedGame) return undefined;
    let active = true;
    loadGameUploadLimit()
      .then((limit) => {
        if (active) {
          setGameUploadLimit(limit);
          setUploadLimitError("");
        }
      })
      .catch((settingsError) => {
        if (active) {
          setGameUploadLimit(null);
          setUploadLimitError(settingsError.message || "Unable to load the configured upload limit.");
        }
      });
    return () => {
      active = false;
    };
  }, [addGameOpen, editingPdfGame?.id, selectedGame?.id]);

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

  useEffect(() => {
    if (loading || !games.length || gameCoverOptimizationStartedRef.current) return;
    gameCoverOptimizationStartedRef.current = true;
    let active = true;

    const runOptimization = async () => {
      let state;
      try {
        state = await loadGameCoverOptimizationState();
      } catch (error) {
        console.error("Unable to read persistent game-cover optimization state.", error);
        return;
      }
      const attempted = new Set(state.attemptedGameIds);
      const candidates = games.filter((game) => {
        const path = String(game.cover_image_url || "");
        return path.startsWith("games/")
          && !path.toLowerCase().endsWith(".webp")
          && !path.includes("/optimized")
          && Boolean(game.cover_display_url)
          && !attempted.has(game.id);
      });
      if (!candidates.length) return;

      setGameCoverOptimizationProgress({ done: 0, total: candidates.length });
      let optimizedCount = 0;
      let skippedCount = 0;
      const failures = [];
      for (let index = 0; index < candidates.length; index += 1) {
        if (!active) return;
        const game = candidates[index];
        let outcome = "failed";
        let uploadedPath = null;
        try {
          const blob = await optimizeExistingGameCover(game.cover_display_url);
          if (!blob) {
            skippedCount += 1;
            outcome = "skipped";
          } else {
            uploadedPath = `games/${game.id}/cover/optimized-${Date.now()}.webp`;
            const { error: uploadError } = await supabase.storage.from("game-assets").upload(uploadedPath, blob, {
              contentType: "image/webp",
              cacheControl: "31536000",
              upsert: false
            });
            if (uploadError) throw uploadError;
            const { data, error: updateError } = await supabase
              .from("games")
              .update({ cover_image_url: uploadedPath })
              .eq("id", game.id)
              .eq("cover_image_url", game.cover_image_url)
              .select("id")
              .maybeSingle();
            if (updateError) throw updateError;
            if (!data) throw new Error("The game cover changed during optimization; the original was retained.");
            optimizedCount += 1;
            outcome = "optimized";
          }
        } catch (error) {
          failures.push(`${game.title || game.id}: ${error?.message || "Unknown error"}`);
          // Keep uploaded files rather than risk deleting an object after an uncertain database update.
        } finally {
          attempted.add(game.id);
          state = {
            ...state,
            version: 1,
            attemptedGameIds: [...attempted],
            optimized: (Number(state.optimized) || 0) + (outcome === "optimized" ? 1 : 0),
            skipped: (Number(state.skipped) || 0) + (outcome === "skipped" ? 1 : 0),
            failed: (Number(state.failed) || 0) + (outcome === "failed" ? 1 : 0),
            lastAttemptAt: new Date().toISOString(),
            status: "in_progress"
          };
          try {
            await saveGameCoverOptimizationState(state);
          } catch (stateError) {
            failures.push(`Progress save for ${game.title || game.id}: ${stateError?.message || "Unable to save progress"}`);
          }
          if (active) setGameCoverOptimizationProgress({ done: index + 1, total: candidates.length });
        }
      }

      state = { ...state, status: "completed", lastCompletedAt: new Date().toISOString() };
      try { await saveGameCoverOptimizationState(state); }
      catch (error) { console.error("Unable to save final game-cover optimization status.", error); }
      await logAdminAction({
        action: "game_covers_bulk_optimized",
        targetType: "game_cover_batch",
        targetName: "Existing game covers",
        details: { candidates: candidates.length, optimized: optimizedCount, skipped: skippedCount, failed: failures.length }
      });
      if (failures.length) {
        console.error("Some game covers could not be optimized:", failures);
        showToast(`Game cover optimization finished: ${optimizedCount} optimized, ${skippedCount} skipped, ${failures.length} failed. See console for failed titles.`, "warning");
      } else {
        showToast(`Game cover optimization finished: ${optimizedCount} optimized, ${skippedCount} skipped.`, "success");
      }
      if (active) {
        setGameCoverOptimizationProgress(null);
        setRefreshKey((current) => current + 1);
      }
    };

    void runOptimization();
    return () => { active = false; };
  }, [games, loading, showToast]);

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
      const deletedGame = await deleteGame(deleteTarget.id);
      const auditSucceeded = await logAdminAction({
        action: "game_deleted",
        targetType: "game",
        targetId: deleteTarget.id,
        targetName: deleteTarget.title,
        details: { soft_deleted: true, removed_storage_assets: 0 }
      }).catch((auditError) => {
        console.error("Game deletion audit logging failed.", {
          gameId: deleteTarget.id,
          code: auditError?.code || auditError?.name || "AUDIT_LOG_FAILED"
        });
        return false;
      });
      setSelectedGame((current) => current?.id === deleteTarget.id ? null : current);
      setAccessGame((current) => current?.id === deleteTarget.id ? null : current);
      setDeleteTarget(null);
      setRefreshKey((current) => current + 1);
      showToast(
        auditSucceeded
          ? `${deleteTarget.title} deleted successfully. Its database records and files were retained.`
          : `${deleteTarget.title} was deleted, but its audit log could not be saved.`,
        auditSucceeded ? "success" : "error"
      );
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
          {gameCoverOptimizationProgress && (
            <p className="muted" role="status">
              Optimizing existing game covers ({gameCoverOptimizationProgress.done}/{gameCoverOptimizationProgress.total})…
            </p>
          )}
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
                    <td><div className="games-name-cell"><GameTableCover src={game.cover_display_url} /><div><strong>{game.title}</strong>{game.subtitle?.trim() ? <span>{game.subtitle}</span> : null}</div></div></td>
                    <td className="games-cards-cell">{game.cardCount}</td>
                    <td className="games-access-cell">
                      <button type="button" className="icon-btn" title="User Access" aria-label={`Manage user access for ${game.title}`} onClick={() => setAccessGame(game)}>
                        <Users size={17} />
                      </button>
                    </td>
                    <td className="games-actions-cell">
                      <div className="actions">
                        <button type="button" className="icon-btn" title="View / Edit" aria-label={`View or edit ${game.title}`} onClick={() => {
                          if (game.game_type === "pdf_deck") setEditingPdfGame(game);
                          else setSelectedGame(game);
                        }}>
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
          gameUploadLimit={gameUploadLimit}
          uploadLimitError={uploadLimitError}
          onClose={() => setSelectedGame(null)}
          onSaved={(updatedGame) => {
            setGames((current) => current.map((game) => game.id === updatedGame.id
              ? { ...game, ...updatedGame }
              : game));
            setSelectedGame(null);
            setRefreshKey((current) => current + 1);
          }}
          showToast={showToast}
        />
      )}
      {addGameOpen && (
        <AddGameModal
          existingGames={games}
          gameUploadLimit={gameUploadLimit}
          uploadLimitError={uploadLimitError}
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
      {editingPdfGame && (
        <AddGameModal
          key={editingPdfGame.id}
          game={editingPdfGame}
          existingGames={games}
          gameUploadLimit={gameUploadLimit}
          uploadLimitError={uploadLimitError}
          onClose={() => setEditingPdfGame(null)}
          onSaved={async (updatedGame) => {
            const auditSucceeded = await logAdminAction({
              action: "game_pdf_updated",
              targetType: "game",
              targetId: updatedGame.id,
              targetName: updatedGame.title,
              details: { format: "PDF deck" }
            }).catch((auditError) => {
              console.error("PDF game update audit logging failed.", {
                gameId: updatedGame.id,
                code: auditError?.code || auditError?.name || "AUDIT_LOG_FAILED"
              });
              return false;
            });
            setEditingPdfGame(null);
            setRefreshKey((current) => current + 1);
            showToast(
              updatedGame.assetCleanupWarning
                ? "Game changes were saved, but some replaced files could not be removed."
                : auditSucceeded
                  ? `${updatedGame.title} saved successfully.`
                  : "Game changes were saved, but the audit log could not be saved.",
              updatedGame.assetCleanupWarning || !auditSucceeded ? "error" : "success"
            );
          }}
          nextSortOrder={Number(editingPdfGame.sort_order) || 0}
          showToast={showToast}
        />
      )}
      {accessGame && (
        <GameUserAccessModal
          key={accessGame.id}
          game={accessGame}
          onClose={() => setAccessGame(null)}
          showToast={showToast}
          ConfirmModal={ConfirmModal}
        />
      )}
      {deleteTarget && (
        <ConfirmModal
          title="Delete Game?"
          message={`Are you sure you want to delete "${deleteTarget.title || "Untitled"}"?`}
          secondaryMessage="This hides the game from the admin and mobile apps while retaining its database record, cards, rules, placements, access settings, payment/purchase history, and uploaded files."
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

function GameUserAccessModal({ game, onClose, showToast, ConfirmModal }) {
  const showToastRef = useRef(showToast);
  showToastRef.current = showToast;
  const [users, setUsers] = useState([]);
  const [purchasedUserIds, setPurchasedUserIds] = useState(() => new Set());
  const [accessOverrides, setAccessOverrides] = useState(() => new Map());
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(false);
  const [search, setSearch] = useState("");
  const [updatingUserIds, setUpdatingUserIds] = useState(() => new Set());
  const [pendingAccessChange, setPendingAccessChange] = useState(null);

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
      return true;
    } catch (error) {
      showToastRef.current(error.message || "Unable to update game user access.", "error");
      return false;
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
                          onChange={(event) => { if (event.target.value !== status) setPendingAccessChange({ user, nextStatus: event.target.value, previousStatus: displayStatus }); }}
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

function AddGameModal({
  game = null,
  existingGames,
  nextSortOrder,
  gameUploadLimit,
  uploadLimitError,
  onClose,
  onCreated,
  onSaved,
  showToast
}) {
  const isEditing = Boolean(game);
  const [form, setForm] = useState(() => ({
    title: game?.title || "",
    subtitle: typeof game?.subtitle === "string" && game.subtitle.trim() ? game.subtitle : "",
    description: typeof game?.description === "string" ? game.description : "",
    rules: "",
    price: String(game?.price ?? 0),
    is_locked: game ? Boolean(game.is_locked) : true
  }));
  const [step, setStep] = useState(1);
  const [gameId, setGameId] = useState(game?.id || "");
  const [errors, setErrors] = useState({});
  const [saving, setSaving] = useState(false);
  const [coverFile, setCoverFile] = useState(null);
  const [coverPreviewUrl, setCoverPreviewUrl] = useState(game?.cover_display_url || game?.cover_image_url || "");
  const [pdfFile, setPdfFile] = useState(null);
  const [pdfDocument, setPdfDocument] = useState(null);
  const [pdfPages, setPdfPages] = useState([]);
  const [selectedPageNumbers, setSelectedPageNumbers] = useState([]);
  const [replaceCardContent, setReplaceCardContent] = useState(false);
  const [pdfLoading, setPdfLoading] = useState(false);
  const [loadingExisting, setLoadingExisting] = useState(isEditing);
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

  useEffect(() => {
    if (!game) return undefined;
    let active = true;
    setLoadingExisting(true);
    Promise.all([
      loadGameDetails(game.id),
      downloadPdfGameSource(game.id, game.source_pdf_path)
    ]).then(async ([result, sourceBlob]) => {
      if (!active) return;
      if (result.rules.error) throw result.rules.error;
      if (result.cards.error) throw result.cards.error;
      const ruleText = result.rules.data[0]?.rule_text || "";
      setForm((current) => ({ ...current, rules: ruleText }));
      const orderedCards = [...result.cards.data].sort((left, right) => (
        (left.metadata?.page_order || left.sort_order) - (right.metadata?.page_order || right.sort_order)
      ));
      const savedPageNumbers = orderedCards.map((card) => card.metadata?.pdf_page_number);
      const sourceFile = new File([sourceBlob], "Current game content.pdf", { type: "application/pdf" });
      const loaded = await loadPdfPreview(sourceFile, savedPageNumbers);
      if (loaded && savedPageNumbers.some((pageNumber) => !Number.isInteger(pageNumber))) {
        setErrors((current) => ({
          ...current,
          pages: "Some saved cards do not contain valid PDF page metadata. Existing images are preserved unless you explicitly replace them."
        }));
      }
    }).catch((loadError) => {
      if (active) {
        console.error("PDF game editor content could not be loaded.", {
          gameId: game.id,
          message: loadError?.message
        });
        setErrors((current) => ({
          ...current,
          pdf: loadError?.message || "Unable to load this game's PDF content."
        }));
      }
    }).finally(() => {
      if (active) setLoadingExisting(false);
    });

    return () => {
      active = false;
    };
  }, [game?.id]);

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

  function clearCoverPreview() {
    if (coverPreviewUrlRef.current) URL.revokeObjectURL(coverPreviewUrlRef.current);
    coverPreviewUrlRef.current = "";
  }

  function chooseCover(event) {
    const file = event.target.files?.[0] || null;
    event.target.value = "";
    if (!file) return;
    if (file && !["image/jpeg", "image/png", "image/webp"].includes(file.type)) {
      clearCoverPreview();
      setCoverPreviewUrl(game?.cover_display_url || game?.cover_image_url || "");
      setCoverFile(null);
      setErrors((current) => ({ ...current, cover: "Choose a JPEG, PNG, or WebP cover image." }));
      return;
    }
    if (!gameUploadLimit) {
      clearCoverPreview();
      setCoverPreviewUrl(game?.cover_display_url || game?.cover_image_url || "");
      setCoverFile(null);
      setErrors((current) => ({ ...current, cover: uploadLimitError || "The configured upload limit is unavailable. Reload the Games page before uploading." }));
      return;
    }
    if (file && file.size > gameUploadLimit.maximumBytes) {
      clearCoverPreview();
      setCoverPreviewUrl(game?.cover_display_url || game?.cover_image_url || "");
      setCoverFile(null);
      setErrors((current) => ({ ...current, cover: gameUploadSizeError(gameUploadLimit) }));
      return;
    }
    clearCoverPreview();
    coverPreviewUrlRef.current = file ? URL.createObjectURL(file) : "";
    setCoverPreviewUrl(coverPreviewUrlRef.current || (game?.cover_display_url || game?.cover_image_url || ""));
    setCoverFile(file);
    setErrors((current) => ({ ...current, cover: "" }));
  }

  async function loadPdfPreview(file, initialSelection = null) {
    const loadId = ++pdfLoadIdRef.current;
    setPdfLoading(true);
    try {
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
        return false;
      }
      pdfDocumentRef.current = document;
      setPdfDocument(document);
      setPdfProgress({ current: 0, total: document.numPages });
      const pages = [];
      for (let pageNumber = 1; pageNumber <= document.numPages; pageNumber += 1) {
        if (loadId !== pdfLoadIdRef.current) {
          await document.destroy();
          return false;
        }
        const page = await document.getPage(pageNumber);
        const previewBlob = await renderPdfPage(page, 240);
        const previewUrl = URL.createObjectURL(previewBlob);
        previewUrlsRef.current.push(previewUrl);
        pages.push({ pageNumber, previewUrl });
        setPdfPages([...pages]);
        setPdfProgress({ current: pageNumber, total: document.numPages });
      }
      const selection = Array.isArray(initialSelection)
        ? initialSelection.filter((pageNumber) => Number.isInteger(pageNumber)
          && pageNumber >= 1
          && pageNumber <= document.numPages)
        : Array.from({ length: document.numPages }, (_, index) => index + 1);
      setSelectedPageNumbers(selection);
      return true;
    } catch (error) {
      if (loadId === pdfLoadIdRef.current) {
        console.error("PDF page preview failed.", { message: error?.message });
        clearPdfPreview();
        setErrors((current) => ({ ...current, pdf: error.message || "Unable to read this PDF. Choose another file." }));
      }
      return false;
    } finally {
      if (loadId === pdfLoadIdRef.current) setPdfLoading(false);
    }
  }

  async function choosePdf(event) {
    const file = event.target.files?.[0] || null;
    event.target.value = "";
    clearPdfPreview();
    setPdfFile(null);
    setReplaceCardContent(false);
    setErrors((current) => ({ ...current, pdf: "", pages: "" }));
    if (!file) return;
    if (!file.type.includes("pdf") && !file.name.toLowerCase().endsWith(".pdf")) {
      setErrors((current) => ({ ...current, pdf: "Choose a PDF file." }));
      return;
    }
    if (!gameUploadLimit) {
      setErrors((current) => ({
        ...current,
        pdf: uploadLimitError || "The configured upload limit is unavailable. Reload the Games page before uploading."
      }));
      return;
    }
    if (file.size > gameUploadLimit.maximumBytes) {
      setErrors((current) => ({ ...current, pdf: gameUploadSizeError(gameUploadLimit) }));
      return;
    }
    setPdfFile(file);
    await loadPdfPreview(file);
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
    if (field === "title" && !isEditing) setGameId("");
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
    const rawPrice = String(form.price).trim();
    const price = Number(rawPrice);
    if (!title) nextErrors.title = "Game title is required.";
    else if (existingGames.some((item) => item.id !== game?.id
      && item.title?.trim().toLocaleLowerCase() === title.toLocaleLowerCase())) {
      nextErrors.title = "A game with this title already exists.";
    }
    if (!form.rules.trim()) nextErrors.rules = "Game rules are required.";
    if (!/^\d+(\.\d{1,2})?$/.test(rawPrice) || !Number.isFinite(price) || price < 0) {
      nextErrors.price = "Enter a valid price of zero or greater, with up to two decimal places.";
    }
    if (!isEditing && !coverFile) nextErrors.cover = "Upload a separate game cover image.";
    if (!isEditing && !gameUploadLimit) {
      nextErrors.pdf = uploadLimitError || "The configured upload limit is unavailable. Reload the Games page before uploading.";
    } else if (!isEditing && (!pdfFile || !pdfDocument)) nextErrors.pdf = "Upload a valid game content PDF.";
    if (isEditing && (pdfFile || replaceCardContent) && !gameUploadLimit) {
      nextErrors.pdf = uploadLimitError || "The configured upload limit is unavailable. Reload the Games page before uploading a replacement.";
    }
    if (isEditing && pdfFile && !replaceCardContent) {
      nextErrors.pdf = "Confirm replacing the saved card faces before uploading a replacement PDF.";
    }
    if (isEditing && replaceCardContent && !pdfDocument) {
      nextErrors.pdf = "Load a valid PDF before replacing the saved card faces.";
    }
    if ((!isEditing || replaceCardContent) && selectedPageNumbers.length === 0) {
      nextErrors.pages = "Select at least one PDF page for the card deck.";
    }
    setErrors(nextErrors);
    return Object.keys(nextErrors).length === 0;
  }

  async function submit(event) {
    event.preventDefault();
    if (!validateDetails()) return;
    if (step === 1) {
      setStep(2);
      return;
    }
    setSaving(true);
    try {
      let pageFiles = null;
      if (!isEditing || replaceCardContent) {
        pageFiles = [];
        for (const pageNumber of selectedPageNumbers) {
          const page = await pdfDocument.getPage(pageNumber);
          pageFiles.push({
            pageNumber,
            blob: await renderPdfPage(page, 3000, "image/png")
          });
        }
      }
      const payload = {
        id: isEditing ? game.id : gameId,
        title: form.title.trim(),
        game_type: "pdf_deck",
        subtitle: form.subtitle.trim(),
        description: form.description.trim(),
        price: form.price.trim(),
        is_locked: Boolean(form.is_locked),
        sort_order: isEditing ? Number(game.sort_order) : nextSortOrder,
        rules: form.rules.trim()
      };
      if (isEditing) {
        const updatedGame = await updatePdfGame(payload, {
          coverFile,
          sourcePdfFile: pdfFile,
          pageFiles
        });
        await onSaved(updatedGame);
      } else {
        const createdGame = await createPdfGame(payload, coverFile, pdfFile, pageFiles);
        await onCreated(createdGame);
      }
    } catch (saveError) {
      if (!isEditing && saveError.message === "A game with this ID already exists.") {
        setGameId(buildGameId(form.title.trim()));
      } else {
        showToast(saveError.message || `Unable to ${isEditing ? "save" : "create"} the game.`, "error");
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
            <h3 id="add-game-title">{step === 1 ? (isEditing ? "Edit Game" : "Add Game") : (isEditing ? "Review Game Changes" : "Review Game")}</h3>
            {step === 2 && <p className="muted">Review the game information and any selected content replacement.</p>}
          </div>
          <button type="button" className="icon-btn" onClick={onClose} disabled={saving} aria-label={`Close ${isEditing ? "Edit" : "Add"} Game`}><X size={20} /></button>
        </div>
        <ConfirmingForm ConfirmModal={ConfirmModal} onConfirm={submit} title={isEditing ? "Save Game Changes?" : "Add This Game?"} message={isEditing ? "Confirm saving the changes to this game." : "Confirm adding this game to the library."} actionLabel={isEditing ? "Save Changes" : "Add Game"} shouldConfirm={step !== 1} className="pdf-game-form" noValidate>
          <div className="modal-body pdf-game-modal-body">
            {step === 1 ? (
              <>
                {loadingExisting && <div className="field-hint">Loading saved game content...</div>}
                <section className="pdf-game-step-section">
                  <h4>Step 1 — Game Information</h4>
                  <label className="pdf-game-field-label" htmlFor="new-game-title">Game Title <span className="required-marker">*</span></label>
                  <input id="new-game-title" value={form.title} onChange={(event) => update("title", event.target.value)} aria-invalid={Boolean(errors.title)} aria-describedby={errors.title ? "new-game-title-error" : undefined} required />
                  {errors.title && <span className="field-error" id="new-game-title-error">{errors.title}</span>}
                  <label className="pdf-game-field-label" htmlFor="new-game-subtitle">Subtitle <span className="muted">(optional)</span></label>
                  <input id="new-game-subtitle" value={form.subtitle} onChange={(event) => update("subtitle", event.target.value)} />
                  <label className="pdf-game-field-label" htmlFor="new-game-description">Description <span className="muted">(optional)</span></label>
                  <textarea id="new-game-description" rows={3} value={form.description} onChange={(event) => update("description", event.target.value)} />
                  <label className="pdf-game-field-label" htmlFor="new-game-rules">Rules <span className="required-marker">*</span></label>
                  <textarea id="new-game-rules" rows={5} value={form.rules} onChange={(event) => update("rules", event.target.value)} aria-invalid={Boolean(errors.rules)} aria-describedby={errors.rules ? "new-game-rules-error" : undefined} required />
                  {errors.rules && <span className="field-error" id="new-game-rules-error">{errors.rules}</span>}
                  <label className="pdf-game-field-label" htmlFor="new-game-price">Price (₱) <span className="required-marker">*</span></label>
                  <input
                    id="new-game-price"
                    type="number"
                    min="0"
                    step="0.01"
                    inputMode="decimal"
                    value={form.price}
                    onChange={(event) => update("price", event.target.value)}
                    aria-invalid={Boolean(errors.price)}
                    aria-describedby={errors.price ? "new-game-price-error" : undefined}
                    required
                  />
                  {errors.price && <span className="field-error" id="new-game-price-error">{errors.price}</span>}
                  <div className="access-box pdf-game-access-box">
                    <div>
                      <strong>Game access</strong>
                      <span className="muted">Locked games can be treated as restricted by your app.</span>
                    </div>
                    <label className="switch-row">
                      <input
                        type="checkbox"
                        checked={Boolean(form.is_locked)}
                        onChange={(event) => update("is_locked", event.target.checked)}
                      />
                      <span>{form.is_locked ? "Locked" : "Free"}</span>
                    </label>
                  </div>
                </section>

                <section className="pdf-game-step-section">
                  <h4>Step 2 — Upload Game Cover</h4>
                  <div className="pdf-game-file-control">
                    <label className="pdf-game-upload" htmlFor="new-game-cover">
                      <ImagePlus size={18} />
                      <span>{coverFile ? `Replace Cover · ${coverFile.name}` : isEditing ? "Choose a replacement cover image (optional)" : <>Choose Game Cover Image <span className="required-marker">*</span></>}</span>
                    </label>
                    <input id="new-game-cover" className="pdf-game-file-input" type="file" accept="image/jpeg,image/png,image/webp" onChange={chooseCover} disabled={saving || !gameUploadLimit} aria-invalid={Boolean(errors.cover)} aria-describedby={errors.cover ? "new-game-cover-error" : undefined} />
                  </div>
                  <span className="field-hint">{gameUploadLimit
                    ? `JPEG, PNG, or WebP; maximum ${gameUploadLimit.maximumMb} MB. The image is kept at its original aspect ratio.`
                    : "Cover upload limit unavailable."}</span>
                  {uploadLimitError && <span className="field-error">{uploadLimitError}</span>}
                  {errors.cover && <span className="field-error" id="new-game-cover-error">{errors.cover}</span>}
                  {isEditing && !coverFile && <span className="field-hint">The saved cover is kept unless you choose a replacement.</span>}
                  {(isEditing || coverPreviewUrl) && <GameCoverFrame src={coverPreviewUrl} className="games-cover-preview-frame" />}
                  {coverFile && <span className="field-hint">{coverFile.name}</span>}
                  {errors.cover && <span className="field-error" id="new-game-cover-error">{errors.cover}</span>}
                </section>

                <section className="pdf-game-step-section">
                  <h4>Step 3 — Upload Game Content PDF</h4>
                  <div className="pdf-game-file-control">
                    <label className="pdf-game-upload" htmlFor="new-game-pdf">
                      <FileText size={18} />
                      <span>{pdfFile ? `Replace PDF · ${pdfFile.name}` : isEditing ? "Choose a replacement PDF (optional)" : <>Choose Game Content PDF <span className="required-marker">*</span></>}</span>
                    </label>
                    <input id="new-game-pdf" className="pdf-game-file-input" type="file" accept="application/pdf,.pdf" onChange={choosePdf} disabled={saving || !gameUploadLimit} aria-invalid={Boolean(errors.pdf)} aria-describedby={errors.pdf ? "new-game-pdf-error" : undefined} />
                  </div>
                  <span className="field-hint">{gameUploadLimit
                    ? `PDF; maximum ${gameUploadLimit.maximumMb} MB. Each selected page becomes one complete card face.`
                    : "PDF; upload limit unavailable. Each selected page becomes one complete card face."}</span>
                  {uploadLimitError && <span className="field-error">{uploadLimitError}</span>}
                  {isEditing && !pdfFile && <span className="field-hint">The current source PDF and saved card-face images are kept unless you explicitly replace the content.</span>}
                  {pdfFile && <span className="field-hint">{pdfFile.name} · {pdfPages.length} {pdfPages.length === 1 ? "page" : "pages"}</span>}
                  {isEditing && (
                    <label className="pdf-game-replace-control">
                      <input
                        type="checkbox"
                        checked={replaceCardContent}
                        onChange={(event) => {
                          setReplaceCardContent(event.target.checked);
                          setErrors((current) => ({ ...current, pdf: "", pages: "" }));
                        }}
                        disabled={saving || pdfLoading || loadingExisting}
                      />
                      <span>Replace the saved card faces with the selected PDF pages. This keeps the same game and deck template, but replaces the current PDF-derived card images.</span>
                    </label>
                  )}
                  {pdfLoading && <span className="field-hint">Rendering page {pdfProgress.current} of {pdfProgress.total}...</span>}
                  {errors.pdf && <span className="field-error" id="new-game-pdf-error">{errors.pdf}</span>}
                  {pdfPages.length > 0 && (
                    <>
                      <div className="pdf-page-heading">
                        <strong>{isEditing && !replaceCardContent ? "Saved PDF pages" : "Select card pages"}{(!isEditing || replaceCardContent) && <> <span className="required-marker">*</span></>}</strong>
                        <span>{selectedPageNumbers.length} selected</span>
                      </div>
                      <span className="field-hint">{isEditing && !replaceCardContent
                        ? "This preview does not alter the saved card images. Enable the replacement option above to apply page selection or ordering changes."
                        : "All pages are selected in their original PDF order. Deselect any page not needed."}</span>
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
              <section className="pdf-game-review" aria-label={isEditing ? "Review game changes" : "Review new game"}>
                <div className="pdf-game-review-heading">
                  {coverPreviewUrl && <img src={coverPreviewUrl} alt={`${form.title.trim()} cover`} />}
                  <div>
                    <h4>{form.title.trim()}</h4>
                    {form.subtitle.trim() ? <span>{form.subtitle.trim()}</span> : null}
                    {form.description.trim() ? <span>{form.description.trim()}</span> : null}
                    <span>Price: ₱{Number(form.price).toFixed(2)}</span>
                    <span>Access: {form.is_locked ? "Locked" : "Free"}</span>
                    <span>{selectedPageNumbers.length} {selectedPageNumbers.length === 1 ? "card" : "cards"}</span>
                  </div>
                </div>
                <div className="pdf-game-review-section">
                  <h4>Rules</h4>
                  <p>{form.rules.trim()}</p>
                </div>
                <div className="pdf-game-review-section">
                  <h4>{replaceCardContent || !isEditing ? "Selected PDF Pages" : "Existing Card Faces"}</h4>
                  {isEditing && !replaceCardContent
                    ? <p>The existing card-face images and page order will remain unchanged.</p>
                    : <>
                      <span className="field-hint">Source PDF: {pdfFile?.name || "Current game content PDF"}</span>
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
                    </>}
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
                if (!isEditing) setGameId(buildGameId(form.title.trim()));
                setStep(2);
              }} disabled={saving || pdfLoading || loadingExisting}>
                {pdfLoading ? "Rendering PDF..." : isEditing ? "Review Changes" : "Review Game"}
              </button>
            ) : (
              <button type="submit" className="primary-btn" disabled={saving || pdfLoading}>
                {saving ? <><Loader2 size={17} className="spin" /> {isEditing ? "Saving..." : "Creating..."}</> : isEditing ? "Save Changes" : "Create Game"}
              </button>
            )}
          </div>
        </ConfirmingForm>
      </div>
      {pendingAccessChange && ConfirmModal && (
        <ConfirmModal
          title="Change Game Access?"
          message={"Confirm changing " + (pendingAccessChange.user.full_name || pendingAccessChange.user.email || "this user") + "'s access for \"" + game.title + "\" from " + pendingAccessChange.previousStatus + " to " + (pendingAccessChange.nextStatus === "free" ? "Free" : "Locked") + "."}
          actionLabel="Confirm Change"
          busyLabel="Updating..."
          tone="primary"
          onClose={() => setPendingAccessChange(null)}
          onConfirm={async () => {
            const { user, nextStatus } = pendingAccessChange;
            const succeeded = await changeUserAccess(user, nextStatus);
            if (succeeded) setPendingAccessChange(null);
            return succeeded;
          }}
        />
      )}
    </div>
  );
}

function GameDetailsModal({ game, gameUploadLimit, uploadLimitError, onClose, onSaved, showToast }) {
  const [details, setDetails] = useState({ rules: [], cards: [] });
  const [loadErrors, setLoadErrors] = useState({});
  const [loading, setLoading] = useState(true);
  const [accessLoaded, setAccessLoaded] = useState(false);
  const [form, setForm] = useState({
    title: game.title || "",
    subtitle: getLegacyGameSubtitle(game),
    description: getGameDescription(game),
    price: String(game.price ?? 0),
    is_locked: Boolean(game.is_locked)
  });
  const [coverFile, setCoverFile] = useState(null);
  const [coverPreviewUrl, setCoverPreviewUrl] = useState(game.cover_display_url || game.cover_image_url || "");
  const [informationErrors, setInformationErrors] = useState({});
  const [savingInfo, setSavingInfo] = useState(false);
  const [cardPage, setCardPage] = useState(0);
  const coverPreviewUrlRef = useRef("");

  useEffect(() => () => {
    if (coverPreviewUrlRef.current) URL.revokeObjectURL(coverPreviewUrlRef.current);
  }, []);

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
      let nextDetails = { rules: [], cards: [] };

      if (detailsResult.status === "rejected") {
        errors.details = detailsResult.reason?.message || "Unable to load game details.";
      } else {
        const result = detailsResult.value;
        if (result.rules.error) errors.rules = result.rules.error.message;
        if (result.cards.error) errors.cards = result.cards.error.message;
        nextDetails = {
          rules: result.rules.data,
          cards: result.cards.data
        };
      }

      if (!active) return;

      if (detailsResult.status === "fulfilled") {
        setForm((current) => ({
          ...current,
          subtitle: current.subtitle === getLegacyGameSubtitle(game)
            ? getLegacyGameSubtitle(game, detailsResult.value.rules.data)
            : current.subtitle,
          description: current.description === getGameDescription(game)
            ? getGameDescription(game, detailsResult.value.rules.data)
            : current.description
        }));
      }

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
    }).finally(() => {
      if (active) setLoading(false);
    });

    return () => {
      active = false;
    };
  }, [game.id]);

  const cardPageCount = Math.ceil(details.cards.length / CARD_PAGE_SIZE);
  const visibleCards = details.cards.slice(cardPage * CARD_PAGE_SIZE, (cardPage + 1) * CARD_PAGE_SIZE);

  function chooseCover(event) {
    const file = event.target.files?.[0] || null;
    event.target.value = "";
    if (!file) return;
    if (!["image/jpeg", "image/png", "image/webp"].includes(file.type)) {
      showToast("Choose a JPEG, PNG, or WebP cover image.", "error");
      return;
    }
    if (!gameUploadLimit) {
      showToast(uploadLimitError || "The configured upload limit is unavailable. Reload the Games page before uploading.", "error");
      return;
    }
    if (file.size > gameUploadLimit.maximumBytes) {
      showToast(gameUploadSizeError(gameUploadLimit), "error");
      return;
    }
    if (coverPreviewUrlRef.current) URL.revokeObjectURL(coverPreviewUrlRef.current);
    coverPreviewUrlRef.current = URL.createObjectURL(file);
    setCoverPreviewUrl(coverPreviewUrlRef.current);
    setCoverFile(file);
  }

  function updateInformationField(field, value) {
    setForm((current) => ({ ...current, [field]: value }));
    setInformationErrors((current) => {
      if (!current[field]) return current;
      const next = { ...current };
      delete next[field];
      return next;
    });
  }

  async function saveInformation(event) {
    event.preventDefault();
    const title = form.title.trim();
    const price = Number(form.price);
    const errors = {};
    if (!title) errors.title = "Enter a game title.";
    if (!/^\d+(?:\.\d{1,2})?$/.test(form.price.trim()) || !Number.isFinite(price) || price < 0) {
      errors.price = "Enter a valid price of zero or greater, with up to two decimal places.";
    }
    setInformationErrors(errors);
    if (Object.keys(errors).length > 0) {
      return;
    }

    const description = form.description.trim();
    const descriptionChanged = description !== (game.description ?? "");
    const subtitle = form.subtitle.trim();
    const subtitleChanged = subtitle !== (game.subtitle ?? "");
    setSavingInfo(true);
    try {
      const updatedGame = await updateGameWithCover(game.id, Boolean(form.is_locked), {
        title,
        ...(subtitleChanged ? { subtitle } : {}),
        ...(descriptionChanged ? { description } : {}),
        price
      }, coverFile);
      const accessChanged = Boolean(game.is_locked) !== Boolean(updatedGame.is_locked);
      const nonAccessChanges = title !== game.title
        || subtitleChanged
        || descriptionChanged
        || price !== Number(game.price || 0)
        || Boolean(coverFile);
      const auditSucceeded = await logAdminAction({
        action: accessChanged && !nonAccessChanges
          ? "game_access_changed"
          : "game_information_updated",
        targetType: "game",
        targetId: updatedGame.id,
        targetName: updatedGame.title,
        details: {
          changed_fields: [
            ...(title !== game.title ? ["title"] : []),
            ...(subtitleChanged ? ["subtitle"] : []),
            ...(descriptionChanged ? ["description"] : []),
            ...(price !== Number(game.price || 0) ? ["price"] : []),
            ...(coverFile ? ["cover image"] : []),
            ...(accessChanged ? ["access"] : [])
          ],
          ...(accessChanged ? { access: updatedGame.is_locked ? "Locked" : "Free" } : {})
        }
      }).catch((auditError) => {
        console.error("Game information audit logging failed.", {
          gameId: updatedGame.id,
          code: auditError?.code || auditError?.name || "AUDIT_LOG_FAILED"
        });
        return false;
      });
      onSaved(updatedGame);
      if (coverPreviewUrlRef.current) URL.revokeObjectURL(coverPreviewUrlRef.current);
      coverPreviewUrlRef.current = "";
      setCoverFile(null);
      setCoverPreviewUrl(updatedGame.cover_display_url || updatedGame.cover_image_url || "");
      setForm({
        title: updatedGame.title || "",
        subtitle: updatedGame.subtitle || "",
        description: updatedGame.description || "",
        price: String(updatedGame.price ?? 0),
        is_locked: Boolean(updatedGame.is_locked)
      });
      showToast(!auditSucceeded
        ? "Game information was saved, but its audit log could not be saved."
        : coverFile
          ? "Game information and cover image saved successfully."
          : accessChanged
            ? `Game information and ${updatedGame.is_locked ? "locked" : "free"} access saved successfully.`
            : "Game information saved successfully.", auditSucceeded ? "success" : "error");
    } catch (saveError) {
      showToast(saveError.message || "Unable to save game information.", "error");
    } finally {
      setSavingInfo(false);
    }
  }

  return (
    <div className="modal-backdrop games-detail-backdrop">
      <div className="modal pdf-game-modal games-detail-modal game-edit-modal" role="dialog" aria-modal="true" aria-labelledby="game-detail-title">
        <div className="modal-header">
          <div><h3 id="game-detail-title">Edit Game</h3><p className="muted">{game.title}</p></div>
          <button type="button" className="icon-btn" onClick={onClose} aria-label="Close game details"><X size={20} /></button>
        </div>
        <div className="games-detail-body">
          {loadErrors.details && <div className="error-box">{loadErrors.details}</div>}
          {loadErrors.access && <div className="error-box">{loadErrors.access}</div>}

          <section className="games-detail-section">
            <h4>Game Information</h4>
            <ConfirmingForm ConfirmModal={ConfirmModal} onConfirm={saveInformation} title="Save Game Information?" message="Confirm saving the changes to this game." actionLabel="Save Changes" id="game-information-form" className="games-info-form" noValidate>
              <label className="pdf-game-field-label" htmlFor="edit-game-title">Game Title <span className="required-marker">*</span></label>
              <input id="edit-game-title" value={form.title} onChange={(event) => updateInformationField("title", event.target.value)} aria-invalid={Boolean(informationErrors.title)} aria-describedby={informationErrors.title ? "edit-game-title-error" : undefined} required />
              {informationErrors.title && <span className="field-error" id="edit-game-title-error">{informationErrors.title}</span>}
              <label className="pdf-game-field-label" htmlFor="edit-game-subtitle">Subtitle <span className="muted">(optional)</span></label>
              <input id="edit-game-subtitle" value={form.subtitle} onChange={(event) => updateInformationField("subtitle", event.target.value)} />
              <label className="pdf-game-field-label" htmlFor="edit-game-description">Description <span className="muted">(optional)</span></label>
              <textarea id="edit-game-description" rows={3} value={form.description} onChange={(event) => updateInformationField("description", event.target.value)} />
              <label className="pdf-game-field-label" htmlFor="edit-game-price">Price (₱) <span className="required-marker">*</span></label>
              <input id="edit-game-price" type="number" min="0" step="0.01" value={form.price} onChange={(event) => updateInformationField("price", event.target.value)} aria-invalid={Boolean(informationErrors.price)} aria-describedby={informationErrors.price ? "edit-game-price-error" : undefined} required />
              {informationErrors.price && <span className="field-error" id="edit-game-price-error">{informationErrors.price}</span>}
              <div className="games-access-field">
                <span className="games-field-label">Game access</span>
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
              <div className="games-cover-detail">
                <span className="games-field-label">Cover Image</span>
                <div className="games-cover-editor">
                  <GameCoverFrame
                    src={coverPreviewUrl}
                    className="games-edit-cover-frame"
                  />
                  <div className="games-cover-editor-controls">
                    <span className="field-hint">{coverFile
                      ? `Previewing ${coverFile.name}`
                      : game.cover_image_url
                        ? "The saved cover will be kept unless you choose a replacement."
                        : "No cover is saved. Upload one to add it to this game."}</span>
                    <span className="field-hint">{gameUploadLimit
                      ? `JPEG, PNG, or WebP; maximum ${gameUploadLimit.maximumMb} MB.`
                      : uploadLimitError || "Cover upload limit unavailable."}</span>
                    <label className="pdf-game-upload games-cover-upload" htmlFor="edit-game-cover">
                      <ImagePlus size={18} />
                      <span>{coverFile
                        ? `Change selected image · ${coverFile.name}`
                        : game.cover_image_url
                          ? "Change Cover Image"
                          : "Upload Cover Image"}</span>
                    </label>
                    <input
                      id="edit-game-cover"
                      className="pdf-game-file-input"
                      type="file"
                      accept="image/jpeg,image/png,image/webp"
                      onChange={chooseCover}
                      disabled={savingInfo || !gameUploadLimit}
                    />
                  </div>
                </div>
              </div>
            </ConfirmingForm>
          </section>

          <section className="games-detail-section">
            <h4>Rules</h4>
            {loadErrors.rules ? <div className="error-box">{loadErrors.rules}</div> : loading ? <p className="field-hint">Loading rules...</p> : details.rules.length === 0 ? (
              <p className="field-hint">No rules have been saved for this game.</p>
            ) : details.rules.map((rule) => (
              <FormattedRule key={rule.id} rule={rule} gameType={game.game_type} />
            ))}
          </section>

          <section className="games-detail-section">
            <div className="games-cards-heading">
              <h4>Cards <span className="muted">({details.cards.length})</span></h4>
              {details.cards.length > CARD_PAGE_SIZE && <div className="games-pagination"><button type="button" className="icon-btn" onClick={() => setCardPage((page) => Math.max(0, page - 1))} disabled={cardPage === 0} aria-label="Previous cards"><ChevronLeft size={18} /></button><span>{cardPage + 1} / {cardPageCount}</span><button type="button" className="icon-btn" onClick={() => setCardPage((page) => Math.min(cardPageCount - 1, page + 1))} disabled={cardPage >= cardPageCount - 1} aria-label="Next cards"><ChevronRight size={18} /></button></div>}
            </div>
            {loadErrors.cards ? <div className="error-box">{loadErrors.cards}</div> : loading ? <p className="field-hint">Loading cards...</p> : details.cards.length === 0 ? <p className="field-hint">No cards have been added for this game.</p> : visibleCards.map((card) => (
              <details className="games-card-entry" key={card.id}>
                <summary>Card {card.sort_order}</summary>
                {LEGACY_METADATA_GAME_TYPES.has(game.game_type) ? (
                  <div className="games-card-fields">
                    <div>
                      {card.front_text?.trim() ? <p>{card.front_text}</p> : null}
                      {card.back_text?.trim() ? <p>{card.back_text}</p> : null}
                    </div>
                  </div>
                ) : (
                  <div className="games-card-fields">
                    <div><span className="muted">Front</span><p>{card.front_text || "—"}</p></div>
                    <div><span className="muted">Back</span><p>{card.back_text || "—"}</p></div>
                  </div>
                )}
              </details>
            ))}
          </section>
        </div>
        <div className="modal-footer">
          <button type="button" className="secondary-btn" onClick={onClose} disabled={savingInfo}>Cancel</button>
          <button type="submit" form="game-information-form" className="primary-btn" disabled={savingInfo || loading || !accessLoaded}>
            {savingInfo ? "Saving..." : "Save Changes"}
          </button>
        </div>
      </div>
    </div>
  );
}
