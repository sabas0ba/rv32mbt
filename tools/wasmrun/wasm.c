/* See wasm.h. Structure: LEB helpers, module parsing, a per-function
 * control-flow map built on first entry, then a switch interpreter. */
#include "wasm.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PAGE_SIZE 65536u
#define FRAME_STACK 256      /* operand slots reserved per call frame */
#define FRAME_LABELS 64      /* branch labels reserved per call frame */
#define MAX_LABELS 256       /* nesting depth the mapper can handle */

/* ---- reader ------------------------------------------------------ */

typedef struct {
  const uint8_t *p, *end;
} Reader;

static uint8_t rd_u8(Reader *r) { return r->p < r->end ? *r->p++ : 0; }

static uint32_t rd_uleb(Reader *r) {
  uint32_t v = 0;
  int shift = 0;
  while (r->p < r->end) {
    uint8_t b = *r->p++;
    v |= (uint32_t)(b & 0x7F) << shift;
    if (!(b & 0x80))
      break;
    shift += 7;
  }
  return v;
}

static int64_t rd_sleb(Reader *r) {
  int64_t v = 0;
  int shift = 0;
  uint8_t b = 0;
  while (r->p < r->end) {
    b = *r->p++;
    v |= (int64_t)(b & 0x7F) << shift;
    shift += 7;
    if (!(b & 0x80))
      break;
  }
  if (shift < 64 && (b & 0x40))
    v -= (int64_t)1 << shift;
  return v;
}

static void skip_bytes(Reader *r, size_t n) { r->p += n; }

/* ---- instruction skipping (used by the control-flow mapper) ------- */

/* Advance `r` past the immediates of opcode `op`. */
static void skip_immediates(Reader *r, uint8_t op) {
  switch (op) {
  case 0x02: case 0x03: case 0x04: { /* block/loop/if: blocktype */
    uint8_t b = *r->p;
    if (b == 0x40 || (b >= 0x7B && b <= 0x7F))
      r->p++;
    else
      rd_sleb(r);
    break;
  }
  case 0x0C: case 0x0D:             /* br, br_if */
  case 0x10:                        /* call */
  case 0x20: case 0x21: case 0x22:  /* local.* */
  case 0x23: case 0x24:             /* global.* */
    rd_uleb(r);
    break;
  case 0x0E: {                      /* br_table */
    uint32_t n = rd_uleb(r);
    for (uint32_t i = 0; i <= n; i++)
      rd_uleb(r);
    break;
  }
  case 0x11:                        /* call_indirect: type, table */
    rd_uleb(r);
    rd_uleb(r);
    break;
  case 0x41:                        /* i32.const */
  case 0x42:                        /* i64.const */
    rd_sleb(r);
    break;
  case 0x43: skip_bytes(r, 4); break;
  case 0x44: skip_bytes(r, 8); break;
  case 0x3F: case 0x40:             /* memory.size/grow */
    rd_u8(r);
    break;
  case 0xFC: {
    uint32_t sub = rd_uleb(r);
    if (sub == 10) { rd_u8(r); rd_u8(r); }   /* memory.copy */
    else if (sub == 11) { rd_u8(r); }        /* memory.fill */
    else if (sub == 8) { rd_uleb(r); rd_u8(r); }
    else if (sub == 9) { rd_uleb(r); }
    break;
  }
  default:
    if (op >= 0x28 && op <= 0x3E) { /* loads and stores: align, offset */
      rd_uleb(r);
      rd_uleb(r);
    }
    break;
  }
}

/* Record, for every block/loop/if in the body, where its else and end
 * are. Offsets are relative to func->body. */
static int map_control_flow(WasmFunc *f) {
  size_t len = (size_t)(f->body_end - f->body);
  f->else_at = calloc(len + 1, sizeof(uint32_t));
  f->end_at = calloc(len + 1, sizeof(uint32_t));
  if (!f->else_at || !f->end_at)
    return -1;

  uint32_t open[MAX_LABELS];
  int depth = 0;
  Reader r = {f->body, f->body_end};
  while (r.p < f->body_end) {
    uint32_t off = (uint32_t)(r.p - f->body);
    uint8_t op = rd_u8(&r);
    if (op == 0x02 || op == 0x03 || op == 0x04) {
      if (depth >= MAX_LABELS)
        return -1;
      open[depth++] = off;
    } else if (op == 0x05) { /* else */
      if (depth > 0)
        f->else_at[open[depth - 1]] = off;
    } else if (op == 0x0B) { /* end */
      if (depth > 0) {
        uint32_t start = open[--depth];
        f->end_at[start] = off;
        if (f->else_at[start])
          f->end_at[f->else_at[start]] = off;
      }
      continue; /* no immediates */
    }
    skip_immediates(&r, op);
  }
  f->mapped = 1;
  return 0;
}

/* A branch target: where control resumes and how much of the operand
 * stack survives the jump. */
typedef struct {
  uint32_t arity;      /* values the branch target expects */
  uint32_t base;       /* operand-stack height the target unwinds to */
  const uint8_t *cont; /* where a branch to this label resumes */
  uint8_t is_loop;
} Label;

/* ---- module parsing ---------------------------------------------- */

/* Evaluate a constant initialiser expression (i32/i64.const or
 * global.get of an already-initialised global). */
static uint64_t eval_const(WasmModule *m, Reader *r) {
  uint64_t v = 0;
  for (;;) {
    uint8_t op = rd_u8(r);
    if (op == 0x0B)
      break;
    if (op == 0x41 || op == 0x42)
      v = (uint64_t)rd_sleb(r);
    else if (op == 0x23) {
      uint32_t g = rd_uleb(r);
      if (g < m->nglobals)
        v = m->globals[g].value;
    }
  }
  return v;
}

static int grow_memory(WasmModule *m, uint32_t pages) {
  uint64_t want = (uint64_t)m->mem_pages + pages;
  if (want > m->mem_max_pages)
    return -1;
  uint8_t *n = realloc(m->mem, (size_t)want * PAGE_SIZE);
  if (!n)
    return -1;
  memset(n + (size_t)m->mem_pages * PAGE_SIZE, 0,
         (size_t)pages * PAGE_SIZE);
  m->mem = n;
  m->mem_pages = (uint32_t)want;
  return 0;
}

int wasm_load(WasmModule *m, const uint8_t *bytes, size_t size) {
  memset(m, 0, sizeof(*m));
  m->bytes = bytes;
  m->size = size;
  m->mem_max_pages = 65536;
  if (size < 8 || memcmp(bytes, "\0asm", 4) != 0) {
    m->error = "not a wasm module";
    return -1;
  }

  Reader r = {bytes + 8, bytes + size};
  uint32_t *func_types = NULL;
  uint32_t nfunc_types = 0;

  while (r.p < r.end) {
    uint8_t id = rd_u8(&r);
    uint32_t sec_size = rd_uleb(&r);
    const uint8_t *sec_end = r.p + sec_size;

    switch (id) {
    case 1: { /* type */
      m->ntypes = rd_uleb(&r);
      m->types = calloc(m->ntypes ? m->ntypes : 1, sizeof(WasmType));
      for (uint32_t i = 0; i < m->ntypes; i++) {
        rd_u8(&r); /* 0x60 */
        WasmType *t = &m->types[i];
        t->nparams = rd_uleb(&r);
        t->params = malloc(t->nparams ? t->nparams : 1);
        for (uint32_t k = 0; k < t->nparams; k++)
          t->params[k] = rd_u8(&r);
        t->nresults = rd_uleb(&r);
        t->results = malloc(t->nresults ? t->nresults : 1);
        for (uint32_t k = 0; k < t->nresults; k++)
          t->results[k] = rd_u8(&r);
      }
      break;
    }
    case 2: { /* import — the module is expected to have none */
      uint32_t n = rd_uleb(&r);
      if (n) {
        m->error = "imports are not supported";
        return -1;
      }
      break;
    }
    case 3: { /* function */
      nfunc_types = rd_uleb(&r);
      func_types = malloc(sizeof(uint32_t) * (nfunc_types ? nfunc_types : 1));
      for (uint32_t i = 0; i < nfunc_types; i++)
        func_types[i] = rd_uleb(&r);
      break;
    }
    case 4: { /* table */
      uint32_t n = rd_uleb(&r);
      for (uint32_t i = 0; i < n; i++) {
        rd_u8(&r); /* element type */
        uint8_t flags = rd_u8(&r);
        uint32_t min = rd_uleb(&r);
        if (flags)
          rd_uleb(&r);
        if (i == 0) {
          m->table_size = min;
          m->table = calloc(min ? min : 1, sizeof(uint32_t));
          for (uint32_t k = 0; k < min; k++)
            m->table[k] = UINT32_MAX;
        }
      }
      break;
    }
    case 5: { /* memory */
      uint32_t n = rd_uleb(&r);
      for (uint32_t i = 0; i < n; i++) {
        uint8_t flags = rd_u8(&r);
        uint32_t min = rd_uleb(&r);
        uint32_t max = flags ? rd_uleb(&r) : 65536;
        if (i == 0) {
          m->mem_max_pages = max;
          m->mem = calloc(min ? (size_t)min * PAGE_SIZE : PAGE_SIZE, 1);
          m->mem_pages = min;
          if (!m->mem) {
            m->error = "out of memory allocating linear memory";
            return -1;
          }
        }
      }
      break;
    }
    case 6: { /* global */
      m->nglobals = rd_uleb(&r);
      m->globals = calloc(m->nglobals ? m->nglobals : 1, sizeof(WasmGlobal));
      for (uint32_t i = 0; i < m->nglobals; i++) {
        m->globals[i].type = rd_u8(&r);
        m->globals[i].mutable_ = rd_u8(&r);
        m->globals[i].value = eval_const(m, &r);
      }
      break;
    }
    case 7: { /* export */
      m->nexports = rd_uleb(&r);
      m->exports = calloc(m->nexports ? m->nexports : 1, sizeof(WasmExport));
      for (uint32_t i = 0; i < m->nexports; i++) {
        uint32_t len = rd_uleb(&r);
        char *name = malloc(len + 1);
        memcpy(name, r.p, len);
        name[len] = 0;
        skip_bytes(&r, len);
        uint8_t kind = rd_u8(&r);
        uint32_t idx = rd_uleb(&r);
        m->exports[i].name = name;
        m->exports[i].func_idx = (kind == 0) ? idx : UINT32_MAX;
      }
      break;
    }
    case 8: /* start */
      m->has_start = 1;
      m->start_func = rd_uleb(&r);
      break;
    case 9: { /* element */
      uint32_t n = rd_uleb(&r);
      for (uint32_t i = 0; i < n; i++) {
        uint32_t flags = rd_uleb(&r);
        uint32_t offset = 0;
        if (flags == 0 || flags == 2) {
          if (flags == 2)
            rd_uleb(&r); /* table index */
          offset = (uint32_t)eval_const(m, &r);
          if (flags == 2)
            rd_u8(&r); /* element kind */
        } else if (flags == 1) {
          rd_u8(&r);
        }
        uint32_t cnt = rd_uleb(&r);
        for (uint32_t k = 0; k < cnt; k++) {
          uint32_t fi = rd_uleb(&r);
          if (m->table && offset + k < m->table_size)
            m->table[offset + k] = fi;
        }
      }
      break;
    }
    case 10: { /* code */
      uint32_t n = rd_uleb(&r);
      m->nfuncs = n;
      m->funcs = calloc(n ? n : 1, sizeof(WasmFunc));
      for (uint32_t i = 0; i < n; i++) {
        uint32_t body_size = rd_uleb(&r);
        const uint8_t *body_end = r.p + body_size;
        uint32_t ndecl = rd_uleb(&r);
        uint32_t total = 0;
        for (uint32_t k = 0; k < ndecl; k++) {
          total += rd_uleb(&r);
          rd_u8(&r);
        }
        m->funcs[i].type_idx = (i < nfunc_types) ? func_types[i] : 0;
        m->funcs[i].nlocals = total;
        m->funcs[i].body = r.p;
        m->funcs[i].body_end = body_end;
        r.p = body_end;
      }
      break;
    }
    case 11: { /* data */
      uint32_t n = rd_uleb(&r);
      for (uint32_t i = 0; i < n; i++) {
        uint32_t flags = rd_uleb(&r);
        uint32_t offset = 0;
        if (flags == 0 || flags == 2) {
          if (flags == 2)
            rd_uleb(&r);
          offset = (uint32_t)eval_const(m, &r);
        }
        uint32_t len = rd_uleb(&r);
        while ((uint64_t)offset + len > (uint64_t)m->mem_pages * PAGE_SIZE) {
          if (grow_memory(m, 1) != 0) {
            m->error = "data segment does not fit in memory";
            return -1;
          }
        }
        memcpy(m->mem + offset, r.p, len);
        skip_bytes(&r, len);
      }
      break;
    }
    default:
      break;
    }
    r.p = sec_end;
  }
  free(func_types);

  /* Execution pools, sized generously enough for this module but
   * still small next to the emulated machine's RAM. */
  m->vstack_size = 16384;
  m->locals_size = 16384;
  m->label_size = 4096;
  m->max_depth = 512;
  m->vstack = malloc(sizeof(uint64_t) * m->vstack_size);
  m->locals_pool = malloc(sizeof(uint64_t) * m->locals_size);
  m->label_pool = malloc(sizeof(Label) * m->label_size);
  if (!m->vstack || !m->locals_pool || !m->label_pool) {
    m->error = "out of memory allocating execution pools";
    return -1;
  }

  if (m->has_start) {
    if (wasm_call(m, m->start_func, NULL, 0, NULL, 0) < 0)
      return -1;
  }
  return 0;
}

void wasm_free(WasmModule *m) {
  for (uint32_t i = 0; i < m->ntypes; i++) {
    free(m->types[i].params);
    free(m->types[i].results);
  }
  free(m->types);
  for (uint32_t i = 0; i < m->nfuncs; i++) {
    free(m->funcs[i].else_at);
    free(m->funcs[i].end_at);
  }
  free(m->funcs);
  free(m->globals);
  for (uint32_t i = 0; i < m->nexports; i++)
    free(m->exports[i].name);
  free(m->exports);
  free(m->table);
  free(m->mem);
  free(m->vstack);
  free(m->locals_pool);
  free(m->label_pool);
  memset(m, 0, sizeof(*m));
}

int wasm_export(WasmModule *m, const char *name) {
  for (uint32_t i = 0; i < m->nexports; i++)
    if (m->exports[i].func_idx != UINT32_MAX &&
        strcmp(m->exports[i].name, name) == 0)
      return (int)m->exports[i].func_idx;
  return -1;
}

/* ---- interpreter -------------------------------------------------- */

/* Resolve a blocktype immediate into (params, results) arity. */
static void block_arity(WasmModule *m, Reader *r, uint32_t *nparams,
                        uint32_t *nresults) {
  uint8_t b = *r->p;
  if (b == 0x40) {
    r->p++;
    *nparams = *nresults = 0;
  } else if (b >= 0x7B && b <= 0x7F) {
    r->p++;
    *nparams = 0;
    *nresults = 1;
  } else {
    int64_t idx = rd_sleb(r);
    if (idx >= 0 && (uint32_t)idx < m->ntypes) {
      *nparams = m->types[idx].nparams;
      *nresults = m->types[idx].nresults;
    } else {
      *nparams = *nresults = 0;
    }
  }
}

#define TRAP(msg)                                                              \
  do {                                                                         \
    m->error = (msg);                                                          \
    return -1;                                                                 \
  } while (0)

#define MEM_CHECK(addr, n)                                                     \
  do {                                                                         \
    if ((uint64_t)(addr) + (n) > (uint64_t)m->mem_pages * PAGE_SIZE)           \
      TRAP("out of bounds memory access");                                     \
  } while (0)

int wasm_call(WasmModule *m, uint32_t idx, const uint64_t *args,
              uint32_t nargs, uint64_t *results, uint32_t max_results) {
  if (idx >= m->nfuncs)
    TRAP("call to an undefined function");
  WasmFunc *f = &m->funcs[idx];
  if (!f->mapped && map_control_flow(f) != 0)
    TRAP("failed to map control flow");
  WasmType *ft = &m->types[f->type_idx];

  if (m->depth >= m->max_depth)
    TRAP("call depth exceeded");

  /* Carve this frame's locals, operands and labels out of the shared
   * pools; the C stack only holds the interpreter's own variables. */
  uint32_t nloc = ft->nparams + f->nlocals;
  uint32_t loc_base = m->locals_sp;
  uint32_t stack_base = m->vsp;
  uint32_t label_base = m->label_sp;
  if (loc_base + nloc > m->locals_size)
    TRAP("locals pool exhausted");
  if (stack_base + FRAME_STACK > m->vstack_size)
    TRAP("operand stack overflow");
  if (label_base + FRAME_LABELS > m->label_size)
    TRAP("label stack overflow");

  uint64_t *locals = m->locals_pool + loc_base;
  uint64_t *stack = m->vstack + stack_base;
  Label *labels = (Label *)m->label_pool + label_base;
  m->locals_sp = loc_base + nloc;
  m->vsp = stack_base + FRAME_STACK;
  m->label_sp = label_base + FRAME_LABELS;
  m->depth++;

  memset(locals, 0, sizeof(uint64_t) * (nloc ? nloc : 1));
  for (uint32_t i = 0; i < nargs && i < ft->nparams; i++)
    locals[i] = args[i];

  uint32_t sp = 0;
  int nlabels = 0;

#define UNWIND()                                                               \
  do {                                                                         \
    m->locals_sp = loc_base;                                                   \
    m->vsp = stack_base;                                                       \
    m->label_sp = label_base;                                                  \
    m->depth--;                                                                \
  } while (0)
#define PUSH(v)                                                                \
  do {                                                                         \
    if (sp >= FRAME_STACK) {                                                   \
      UNWIND();                                                                \
      TRAP("operand stack overflow");                                          \
    }                                                                          \
    stack[sp++] = (uint64_t)(v);                                               \
  } while (0)
#define POP() (stack[--sp])
#define POP32() ((uint32_t)stack[--sp])
#define POP32S() ((int32_t)(uint32_t)stack[--sp])
#define FAIL(msg)                                                              \
  do {                                                                         \
    UNWIND();                                                                  \
    TRAP(msg);                                                                 \
  } while (0)

  Reader r = {f->body, f->body_end};
  uint32_t branch_depth = 0;

  for (;;) {
    if (r.p >= f->body_end)
      break;
    uint32_t off = (uint32_t)(r.p - f->body);
    uint8_t op = rd_u8(&r);

    switch (op) {
    case 0x00:
      FAIL("unreachable executed");
    case 0x01:
      break;

    case 0x02: case 0x03: case 0x04: { /* block, loop, if */
      uint32_t np, nr;
      const uint8_t *after_bt;
      block_arity(m, &r, &np, &nr);
      after_bt = r.p;
      uint32_t cond = 1;
      if (op == 0x04)
        cond = POP32();
      if (nlabels >= (int)FRAME_LABELS)
        FAIL("label stack overflow");
      Label *l = &labels[nlabels++];
      l->is_loop = (op == 0x03);
      l->arity = l->is_loop ? np : nr;
      l->base = sp - np;
      l->cont = l->is_loop ? after_bt : f->body + f->end_at[off] + 1;
      if (op == 0x04 && !cond) {
        /* Skip the then-branch. With an else, resume just past it;
         * without one, land on the `end`, which pops the label. */
        uint32_t e = f->else_at[off];
        r.p = e ? f->body + e + 1 : f->body + f->end_at[off];
      }
      break;
    }

    case 0x05: /* else: the then-branch fell through, skip to end */
      r.p = f->body + f->end_at[off];
      break;

    case 0x0B: /* end */
      if (nlabels == 0)
        goto done;
      nlabels--;
      break;

    case 0x0C: case 0x0D: { /* br, br_if */
      branch_depth = rd_uleb(&r);
      if (op == 0x0D && !POP32())
        break;
      goto do_branch;
    }

    case 0x0E: { /* br_table */
      uint32_t n = rd_uleb(&r);
      uint32_t chosen = 0;
      uint32_t i = POP32();
      for (uint32_t k = 0; k < n; k++) {
        uint32_t d = rd_uleb(&r);
        if (k == i)
          chosen = d;
      }
      uint32_t dflt = rd_uleb(&r);
      branch_depth = (i < n) ? chosen : dflt;
      goto do_branch;
    }

    do_branch: {
      if ((int)branch_depth >= nlabels)
        FAIL("branch out of range");
      Label *l = &labels[nlabels - 1 - branch_depth];
      uint32_t a = l->arity;
      for (uint32_t i = 0; i < a; i++)
        stack[l->base + i] = stack[sp - a + i];
      sp = l->base + a;
      nlabels = (int)(nlabels - 1 - branch_depth) + (l->is_loop ? 1 : 0);
      r.p = l->cont;
      break;
    }

    case 0x0F: /* return */
      goto done;

    case 0x10: case 0x11: { /* call, call_indirect */
      uint32_t fidx;
      if (op == 0x10) {
        fidx = rd_uleb(&r);
      } else {
        rd_uleb(&r); /* expected type */
        rd_uleb(&r); /* table */
        uint32_t ti = POP32();
        if (!m->table || ti >= m->table_size)
          FAIL("undefined element in table");
        fidx = m->table[ti];
        if (fidx == UINT32_MAX)
          FAIL("uninitialized element");
      }
      if (fidx >= m->nfuncs)
        FAIL("call to an undefined function");
      WasmType *ct = &m->types[m->funcs[fidx].type_idx];
      if (sp < ct->nparams)
        FAIL("operand stack underflow at call");
      uint64_t res[16];
      int n = wasm_call(m, fidx, stack + sp - ct->nparams, ct->nparams, res,
                        16);
      if (n < 0) {
        UNWIND();
        return -1;
      }
      sp -= ct->nparams;
      for (int i = 0; i < n; i++)
        PUSH(res[i]);
      break;
    }

    case 0x1A: sp--; break;                       /* drop */
    case 0x1B: {                                  /* select */
      uint32_t c = POP32();
      uint64_t b = POP(), a = POP();
      PUSH(c ? a : b);
      break;
    }

    case 0x20: PUSH(locals[rd_uleb(&r)]); break;  /* local.get */
    case 0x21: { uint32_t i = rd_uleb(&r); locals[i] = POP(); break; }
    case 0x22: { uint32_t i = rd_uleb(&r); locals[i] = stack[sp - 1]; break; }
    case 0x23: PUSH(m->globals[rd_uleb(&r)].value); break;
    case 0x24: { uint32_t i = rd_uleb(&r); m->globals[i].value = POP(); break; }

    /* loads: align, offset immediates then addr from the stack */
    case 0x28: case 0x29: case 0x2C: case 0x2D: case 0x2E: case 0x2F:
    case 0x30: case 0x31: case 0x32: case 0x33: case 0x34: case 0x35: {
      rd_uleb(&r);
      uint32_t o = rd_uleb(&r);
      uint32_t a = POP32() + o;
      uint8_t *p;
      switch (op) {
      case 0x28: MEM_CHECK(a, 4); p = m->mem + a;
        PUSH((uint64_t)(uint32_t)(p[0] | p[1] << 8 | p[2] << 16 |
                                  (uint32_t)p[3] << 24));
        break;
      case 0x29: case 0x34: case 0x35: {
        MEM_CHECK(a, op == 0x29 ? 8 : 4);
        p = m->mem + a;
        uint32_t lo = p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24;
        if (op == 0x29) {
          uint32_t hi = p[4] | p[5] << 8 | p[6] << 16 | (uint32_t)p[7] << 24;
          PUSH(((uint64_t)hi << 32) | lo);
        } else if (op == 0x34) {
          PUSH((uint64_t)(int64_t)(int32_t)lo);
        } else {
          PUSH((uint64_t)lo);
        }
        break;
      }
      case 0x2C: MEM_CHECK(a, 1);
        PUSH((uint64_t)(uint32_t)(int32_t)(int8_t)m->mem[a]); break;
      case 0x2D: MEM_CHECK(a, 1); PUSH((uint64_t)m->mem[a]); break;
      case 0x2E: MEM_CHECK(a, 2); p = m->mem + a;
        PUSH((uint64_t)(uint32_t)(int32_t)(int16_t)(p[0] | p[1] << 8)); break;
      case 0x2F: MEM_CHECK(a, 2); p = m->mem + a;
        PUSH((uint64_t)(uint32_t)(p[0] | p[1] << 8)); break;
      case 0x30: MEM_CHECK(a, 1);
        PUSH((uint64_t)(int64_t)(int8_t)m->mem[a]); break;
      case 0x31: MEM_CHECK(a, 1); PUSH((uint64_t)m->mem[a]); break;
      case 0x32: MEM_CHECK(a, 2); p = m->mem + a;
        PUSH((uint64_t)(int64_t)(int16_t)(p[0] | p[1] << 8)); break;
      case 0x33: MEM_CHECK(a, 2); p = m->mem + a;
        PUSH((uint64_t)(uint32_t)(p[0] | p[1] << 8)); break;
      }
      break;
    }

    /* stores: value then addr are on the stack (addr pushed first) */
    case 0x36: case 0x37: case 0x3A: case 0x3B: case 0x3C: case 0x3D:
    case 0x3E: {
      rd_uleb(&r);
      uint32_t o = rd_uleb(&r);
      uint64_t v = POP();
      uint32_t a = POP32() + o;
      uint8_t *p;
      switch (op) {
      case 0x36: case 0x3E: MEM_CHECK(a, 4); p = m->mem + a;
        p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8);
        p[2] = (uint8_t)(v >> 16); p[3] = (uint8_t)(v >> 24);
        break;
      case 0x37: MEM_CHECK(a, 8); p = m->mem + a;
        for (int i = 0; i < 8; i++)
          p[i] = (uint8_t)(v >> (8 * i));
        break;
      case 0x3A: case 0x3C: MEM_CHECK(a, 1); m->mem[a] = (uint8_t)v; break;
      case 0x3B: case 0x3D: MEM_CHECK(a, 2); p = m->mem + a;
        p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8);
        break;
      }
      break;
    }

    case 0x3F: rd_u8(&r); PUSH((uint64_t)m->mem_pages); break;
    case 0x40: {
      rd_u8(&r);
      uint32_t n = POP32();
      uint32_t old = m->mem_pages;
      if (grow_memory(m, n) != 0)
        PUSH((uint64_t)(uint32_t)-1);
      else
        PUSH((uint64_t)old);
      break;
    }

    case 0x41: PUSH((uint64_t)(uint32_t)(int32_t)rd_sleb(&r)); break;
    case 0x42: PUSH((uint64_t)rd_sleb(&r)); break;

    /* i32 comparisons */
    case 0x45: { uint32_t a = POP32(); PUSH(a == 0); break; }
    case 0x46: { uint32_t b = POP32(), a = POP32(); PUSH(a == b); break; }
    case 0x47: { uint32_t b = POP32(), a = POP32(); PUSH(a != b); break; }
    case 0x48: { int32_t b = POP32S(), a = POP32S(); PUSH(a < b); break; }
    case 0x49: { uint32_t b = POP32(), a = POP32(); PUSH(a < b); break; }
    case 0x4A: { int32_t b = POP32S(), a = POP32S(); PUSH(a > b); break; }
    case 0x4B: { uint32_t b = POP32(), a = POP32(); PUSH(a > b); break; }
    case 0x4C: { int32_t b = POP32S(), a = POP32S(); PUSH(a <= b); break; }
    case 0x4D: { uint32_t b = POP32(), a = POP32(); PUSH(a <= b); break; }
    case 0x4E: { int32_t b = POP32S(), a = POP32S(); PUSH(a >= b); break; }
    case 0x4F: { uint32_t b = POP32(), a = POP32(); PUSH(a >= b); break; }

    /* i64 comparisons */
    case 0x50: { uint64_t a = POP(); PUSH(a == 0); break; }
    case 0x51: { uint64_t b = POP(), a = POP(); PUSH(a == b); break; }
    case 0x52: { uint64_t b = POP(), a = POP(); PUSH(a != b); break; }
    case 0x53: { int64_t b = (int64_t)POP(), a = (int64_t)POP(); PUSH(a < b); break; }
    case 0x54: { uint64_t b = POP(), a = POP(); PUSH(a < b); break; }
    case 0x55: { int64_t b = (int64_t)POP(), a = (int64_t)POP(); PUSH(a > b); break; }
    case 0x56: { uint64_t b = POP(), a = POP(); PUSH(a > b); break; }
    case 0x57: { int64_t b = (int64_t)POP(), a = (int64_t)POP(); PUSH(a <= b); break; }
    case 0x58: { uint64_t b = POP(), a = POP(); PUSH(a <= b); break; }
    case 0x59: { int64_t b = (int64_t)POP(), a = (int64_t)POP(); PUSH(a >= b); break; }
    case 0x5A: { uint64_t b = POP(), a = POP(); PUSH(a >= b); break; }

    /* i32 arithmetic */
    case 0x67: { uint32_t a = POP32(); int n = 0;
      if (!a) n = 32; else while (!(a & 0x80000000u)) { a <<= 1; n++; }
      PUSH((uint32_t)n); break; }
    case 0x68: { uint32_t a = POP32(); int n = 0;
      if (!a) n = 32; else while (!(a & 1)) { a >>= 1; n++; }
      PUSH((uint32_t)n); break; }
    case 0x69: { uint32_t a = POP32(); int n = 0;
      while (a) { n += a & 1; a >>= 1; }
      PUSH((uint32_t)n); break; }
    case 0x6A: { uint32_t b = POP32(), a = POP32(); PUSH((uint32_t)(a + b)); break; }
    case 0x6B: { uint32_t b = POP32(), a = POP32(); PUSH((uint32_t)(a - b)); break; }
    case 0x6C: { uint32_t b = POP32(), a = POP32(); PUSH((uint32_t)(a * b)); break; }
    case 0x6D: { int32_t b = POP32S(), a = POP32S();
      if (!b) FAIL("integer divide by zero");
      if (a == INT32_MIN && b == -1) FAIL("integer overflow");
      PUSH((uint32_t)(a / b)); break; }
    case 0x6E: { uint32_t b = POP32(), a = POP32();
      if (!b) FAIL("integer divide by zero");
      PUSH(a / b); break; }
    case 0x6F: { int32_t b = POP32S(), a = POP32S();
      if (!b) FAIL("integer divide by zero");
      PUSH((uint32_t)(b == -1 ? 0 : a % b)); break; }
    case 0x70: { uint32_t b = POP32(), a = POP32();
      if (!b) FAIL("integer divide by zero");
      PUSH(a % b); break; }
    case 0x71: { uint32_t b = POP32(), a = POP32(); PUSH(a & b); break; }
    case 0x72: { uint32_t b = POP32(), a = POP32(); PUSH(a | b); break; }
    case 0x73: { uint32_t b = POP32(), a = POP32(); PUSH(a ^ b); break; }
    case 0x74: { uint32_t b = POP32(), a = POP32(); PUSH(a << (b & 31)); break; }
    case 0x75: { uint32_t b = POP32(); int32_t a = POP32S();
      PUSH((uint32_t)(a >> (b & 31))); break; }
    case 0x76: { uint32_t b = POP32(), a = POP32(); PUSH(a >> (b & 31)); break; }
    case 0x77: { uint32_t b = POP32() & 31, a = POP32();
      PUSH(b ? ((a << b) | (a >> (32 - b))) : a); break; }
    case 0x78: { uint32_t b = POP32() & 31, a = POP32();
      PUSH(b ? ((a >> b) | (a << (32 - b))) : a); break; }

    /* i64 arithmetic */
    case 0x79: { uint64_t a = POP(); int n = 0;
      if (!a) n = 64; else while (!(a & 0x8000000000000000ull)) { a <<= 1; n++; }
      PUSH((uint64_t)n); break; }
    case 0x7A: { uint64_t a = POP(); int n = 0;
      if (!a) n = 64; else while (!(a & 1)) { a >>= 1; n++; }
      PUSH((uint64_t)n); break; }
    case 0x7B: { uint64_t a = POP(); int n = 0;
      while (a) { n += a & 1; a >>= 1; }
      PUSH((uint64_t)n); break; }
    case 0x7C: { uint64_t b = POP(), a = POP(); PUSH(a + b); break; }
    case 0x7D: { uint64_t b = POP(), a = POP(); PUSH(a - b); break; }
    case 0x7E: { uint64_t b = POP(), a = POP(); PUSH(a * b); break; }
    case 0x7F: { int64_t b = (int64_t)POP(), a = (int64_t)POP();
      if (!b) FAIL("integer divide by zero");
      if (a == INT64_MIN && b == -1) FAIL("integer overflow");
      PUSH((uint64_t)(a / b)); break; }
    case 0x80: { uint64_t b = POP(), a = POP();
      if (!b) FAIL("integer divide by zero");
      PUSH(a / b); break; }
    case 0x81: { int64_t b = (int64_t)POP(), a = (int64_t)POP();
      if (!b) FAIL("integer divide by zero");
      PUSH((uint64_t)(b == -1 ? 0 : a % b)); break; }
    case 0x82: { uint64_t b = POP(), a = POP();
      if (!b) FAIL("integer divide by zero");
      PUSH(a % b); break; }
    case 0x83: { uint64_t b = POP(), a = POP(); PUSH(a & b); break; }
    case 0x84: { uint64_t b = POP(), a = POP(); PUSH(a | b); break; }
    case 0x85: { uint64_t b = POP(), a = POP(); PUSH(a ^ b); break; }
    case 0x86: { uint64_t b = POP(), a = POP(); PUSH(a << (b & 63)); break; }
    case 0x87: { uint64_t b = POP(); int64_t a = (int64_t)POP();
      PUSH((uint64_t)(a >> (b & 63))); break; }
    case 0x88: { uint64_t b = POP(), a = POP(); PUSH(a >> (b & 63)); break; }
    case 0x89: { uint64_t b = POP() & 63, a = POP();
      PUSH(b ? ((a << b) | (a >> (64 - b))) : a); break; }
    case 0x8A: { uint64_t b = POP() & 63, a = POP();
      PUSH(b ? ((a >> b) | (a << (64 - b))) : a); break; }

    /* conversions */
    case 0xA7: { uint64_t a = POP(); PUSH((uint64_t)(uint32_t)a); break; }
    case 0xAC: { int32_t a = POP32S(); PUSH((uint64_t)(int64_t)a); break; }
    case 0xAD: { uint32_t a = POP32(); PUSH((uint64_t)a); break; }

    /* sign extension */
    case 0xC0: { int8_t a = (int8_t)POP32(); PUSH((uint32_t)(int32_t)a); break; }
    case 0xC1: { int16_t a = (int16_t)POP32(); PUSH((uint32_t)(int32_t)a); break; }
    case 0xC2: { int8_t a = (int8_t)POP(); PUSH((uint64_t)(int64_t)a); break; }
    case 0xC3: { int16_t a = (int16_t)POP(); PUSH((uint64_t)(int64_t)a); break; }
    case 0xC4: { int32_t a = (int32_t)POP(); PUSH((uint64_t)(int64_t)a); break; }

    case 0xFC: { /* bulk memory */
      uint32_t sub = rd_uleb(&r);
      if (sub == 10) { /* memory.copy */
        rd_u8(&r); rd_u8(&r);
        uint32_t n = POP32(), s = POP32(), d = POP32();
        MEM_CHECK(s, n);
        MEM_CHECK(d, n);
        memmove(m->mem + d, m->mem + s, n);
      } else if (sub == 11) { /* memory.fill */
        rd_u8(&r);
        uint32_t n = POP32(), v = POP32(), d = POP32();
        MEM_CHECK(d, n);
        memset(m->mem + d, (int)(v & 0xFF), n);
      } else {
        FAIL("unsupported 0xFC instruction");
      }
      break;
    }

    default:
      FAIL("unsupported opcode");
    }
  }

done: {
    if (sp < ft->nresults)
      FAIL("function returned fewer results than its type declares");
    uint32_t n = ft->nresults;
    if (n > max_results)
      n = max_results;
    for (uint32_t i = 0; i < n; i++)
      results[i] = stack[sp - ft->nresults + i];
    UNWIND();
    return (int)n;
  }
}
