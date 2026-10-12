function emphasizePhrases(text, phrases) {
  const parts = [];
  let offset = 0;

  while (offset < text.length) {
    const match = phrases
      .map((phrase) => ({ phrase, index: text.indexOf(phrase, offset) }))
      .filter(({ index }) => index >= 0)
      .sort((left, right) => left.index - right.index)[0];

    if (!match) {
      parts.push({ text: text.slice(offset) });
      break;
    }

    if (match.index > offset) {
      parts.push({ text: text.slice(offset, match.index) });
    }
    parts.push({ text: match.phrase, bold: true });
    offset = match.index + match.phrase.length;
  }

  return parts;
}

export function parseInlineFormatting(text) {
  const segments = [];
  const source = String(text ?? "");
  const pattern = /\*\*([^*]+)\*\*|\[(bold|underlined)\](.*?)\[\/\2\]/g;
  let lastIndex = 0;
  let match;

  while ((match = pattern.exec(source))) {
    if (match.index > lastIndex) {
      segments.push({ type: "text", text: source.slice(lastIndex, match.index) });
    }

    segments.push({
      type: match[2] === "underlined" ? "underline" : "bold",
      text: match[1] ?? match[3]
    });
    lastIndex = match.index + match[0].length;
  }

  if (lastIndex < source.length) {
    segments.push({ type: "text", text: source.slice(lastIndex) });
  }

  return segments;
}

function ruleItem(text, boldPhrases = []) {
  return { text, parts: emphasizePhrases(text, boldPhrases), children: [] };
}

function orderedList(start, items) {
  return {
    type: "list",
    list: { type: "ordered", indent: 0, start, items, parentItem: null }
  };
}

function unorderedList(items) {
  return {
    type: "list",
    list: { type: "unordered", indent: 0, items, parentItem: null }
  };
}

function paragraph(item) {
  return { type: "paragraph", item };
}

function getBibleGroupsBlocks(sourceRule) {
  const rules = sourceRule?.rules;
  if (!Array.isArray(rules) || rules.length !== 6 || !rules.every((rule) => typeof rule === "string")) {
    return null;
  }

  const example = rules[2].match(/^For example:\s*(.*?)\s+(Within one minute,.*)$/);
  const scoring = rules[4].match(/^Scoring:\s*(.*)$/);
  const scoringItems = scoring?.[1].match(/[^.]+(?:\.|$)/g)?.map((item) => item.trim()) ?? [];
  if (!example || scoringItems.length !== 3) {
    return null;
  }

  return [
    orderedList(1, [
      ruleItem(rules[0], ["two (2) teams"]),
      ruleItem(rules[1], ["The Game Master will read aloud"])
    ]),
    paragraph(ruleItem("For example:")),
    unorderedList([
      ruleItem(example[1]),
      ruleItem(example[2])
    ]),
    orderedList(3, [
      ruleItem(rules[3])
    ]),
    paragraph(ruleItem("Scoring:", ["Scoring:"])),
    unorderedList(scoringItems.map((item) => ruleItem(item))),
    orderedList(4, [
      ruleItem(rules[5], ["The first team to win 40 points wins."])
    ])
  ];
}

function getBibleTalkBlocks(sourceRule) {
  const rules = sourceRule?.rules;
  if (
    !Array.isArray(rules)
    || rules.length !== 5
    || !rules.every((rule) => typeof rule === "string")
    || rules[2] !== "For example:"
  ) {
    return null;
  }

  return [
    orderedList(1, [
      ruleItem(rules[0], ["two (2) teams,"]),
      ruleItem(rules[1], ['"Describe using words"', "five"])
    ]),
    paragraph(ruleItem(rules[2])),
    unorderedList([
      ruleItem(rules[3])
    ]),
    orderedList(3, [
      ruleItem(rules[4], ["1 minute,", "The first team to win 15 points wins."])
    ])
  ];
}

export function getLegacyGameRuleBlocks(gameType, sourceRule) {
  if (gameType === "bible_groups") {
    return getBibleGroupsBlocks(sourceRule);
  }
  if (gameType === "bible_talk") {
    return getBibleTalkBlocks(sourceRule);
  }
  return null;
}
