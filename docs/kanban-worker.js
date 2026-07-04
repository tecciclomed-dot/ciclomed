/**
 * Worker Cloudflare — proxy Protheus + API Kanban (KV)
 *
 * SETUP (uma vez no dashboard Cloudflare):
 * 1. Workers & Pages → repouso ciclomedo → Settings → Bindings
 * 2. Add binding → KV namespace → Name: KANBAN_KV → Create namespace "ciclomed-kanban"
 * 3. Cole este arquivo inteiro no editor e clique Deploy
 */
const KANBAN_KEY = "board";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname.startsWith("/kanban")) {
      return handleKanban(request, env, url);
    }

    return proxyProtheus(request, url);
  },

  async scheduled(event, env, ctx) {
    const BACKEND = "http://ciclomed161112.protheus.cloudtotvs.com.br:1557";
    const BASIC_AUTH = "Basic " + btoa("admin:Ciclo@!9751!");
    try {
      await fetch(BACKEND + "/rest03/WSSOLPV?acao=versao", {
        headers: { Authorization: BASIC_AUTH },
        signal: AbortSignal.timeout(20000),
      });
    } catch (_) {}
  },
};

async function proxyProtheus(request, url) {
  const BACKEND = "http://ciclomed161112.protheus.cloudtotvs.com.br:1557";
  const BASIC_AUTH = "Basic " + btoa("admin:Ciclo@!9751!");

  if (request.method === "OPTIONS") {
    return new Response(null, { headers: CORS });
  }

  const backendUrl = BACKEND + url.pathname + url.search;
  const backendRequest = new Request(backendUrl, {
    method: request.method,
    headers: {
      Authorization: BASIC_AUTH,
      "Content-Type": "application/json",
    },
    body: request.method !== "GET" && request.method !== "HEAD" ? request.body : undefined,
  });

  try {
    const response = await fetch(backendRequest, {
      signal: AbortSignal.timeout(55000),
    });
    const newResponse = new Response(response.body, response);
    newResponse.headers.set("Access-Control-Allow-Origin", "*");
    return newResponse;
  } catch (err) {
    return json(
      { ok: false, msg: "Protheus timeout: " + err.message },
      504
    );
  }
}

async function handleKanban(request, env, url) {
  if (request.method === "OPTIONS") {
    return new Response(null, { headers: CORS });
  }

  if (!env.KANBAN_KV) {
    return json(
      {
        ok: false,
        erro: "KV nao configurado. Adicione binding KANBAN_KV no worker.",
      },
      503
    );
  }

  try {
    const path = url.pathname.replace(/^\/kanban\/?/, "");
    const parts = path.split("/").filter(Boolean);

    if (request.method === "GET" && parts.length === 0) {
      const board = await loadBoard(env);
      return json({ ok: true, board });
    }

    if (request.method === "POST" && parts[0] === "cards" && parts.length === 1) {
      const body = await request.json();
      const board = await loadBoard(env);
      const user = str(body.user) || "Anonimo";
      const now = isoNow();
      const card = {
        id: crypto.randomUUID(),
        columnId: validColumn(body.columnId) || "aberto",
        title: str(body.title) || "Novo projeto",
        description: str(body.description),
        priority: validPriority(body.priority),
        assignee: str(body.assignee),
        createdAt: now,
        createdBy: user,
        updatedAt: now,
        history: [
          {
            at: now,
            user,
            action: "created",
            from: null,
            to: validColumn(body.columnId) || "aberto",
          },
        ],
      };
      board.cards.unshift(card);
      board.updatedAt = now;
      await saveBoard(env, board);
      return json({ ok: true, card, board });
    }

    if (parts[0] === "cards" && parts.length >= 2) {
      const cardId = parts[1];
      const board = await loadBoard(env);
      const idx = board.cards.findIndex((c) => c.id === cardId);
      if (idx < 0) return json({ ok: false, erro: "Card nao encontrado" }, 404);
      const card = board.cards[idx];

      if (request.method === "PUT" && parts.length === 2) {
        const body = await request.json();
        const user = str(body.user) || "Anonimo";
        const now = isoNow();
        const changed = [];
        if (body.title !== undefined && str(body.title) !== card.title) {
          card.title = str(body.title) || card.title;
          changed.push("titulo");
        }
        if (body.description !== undefined && str(body.description) !== card.description) {
          card.description = str(body.description);
          changed.push("descricao");
        }
        if (body.priority !== undefined && validPriority(body.priority) !== card.priority) {
          card.priority = validPriority(body.priority);
          changed.push("prioridade");
        }
        if (body.assignee !== undefined && str(body.assignee) !== card.assignee) {
          card.assignee = str(body.assignee);
          changed.push("responsavel");
        }
        if (changed.length) {
          card.updatedAt = now;
          pushHistory(card, {
            at: now,
            user,
            action: "updated",
            fields: changed,
          });
          board.updatedAt = now;
          await saveBoard(env, board);
        }
        return json({ ok: true, card, board });
      }

      if (request.method === "PATCH" && parts.length === 3 && parts[2] === "move") {
        const body = await request.json();
        const user = str(body.user) || "Anonimo";
        const to = validColumn(body.columnId);
        if (!to) return json({ ok: false, erro: "Coluna invalida" }, 400);
        const from = card.columnId;
        if (from === to) return json({ ok: true, card, board });
        const now = isoNow();
        card.columnId = to;
        card.updatedAt = now;
        pushHistory(card, { at: now, user, action: "moved", from, to });
        board.updatedAt = now;
        await saveBoard(env, board);
        return json({ ok: true, card, board });
      }

      if (request.method === "DELETE" && parts.length === 2) {
        const user = url.searchParams.get("user") || "Anonimo";
        const now = isoNow();
        board.cards.splice(idx, 1);
        board.updatedAt = now;
        await saveBoard(env, board);
        return json({ ok: true, deleted: cardId, user, board });
      }
    }

    return json({ ok: false, erro: "Rota nao encontrada" }, 404);
  } catch (err) {
    return json({ ok: false, erro: err.message }, 500);
  }
}

async function loadBoard(env) {
  const raw = await env.KANBAN_KV.get(KANBAN_KEY);
  if (!raw) {
    return { version: 1, updatedAt: isoNow(), cards: [] };
  }
  return JSON.parse(raw);
}

async function saveBoard(env, board) {
  await env.KANBAN_KV.put(KANBAN_KEY, JSON.stringify(board));
}

function pushHistory(card, entry) {
  if (!Array.isArray(card.history)) card.history = [];
  card.history.unshift(entry);
  if (card.history.length > 100) card.history.length = 100;
}

function validColumn(id) {
  return ["aberto", "atendimento", "concluido"].includes(id) ? id : null;
}

function validPriority(p) {
  return ["baixa", "media", "alta"].includes(p) ? p : "media";
}

function str(v) {
  return v == null ? "" : String(v).trim();
}

function isoNow() {
  return new Date().toISOString();
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, "Content-Type": "application/json;charset=utf-8" },
  });
}
