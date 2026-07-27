/* A small WebAssembly interpreter, scoped to what the rv32mbt core
 * module actually uses: the integer MVP instruction set plus
 * memory.copy/fill, multi-value blocks and call_indirect. No floats,
 * no imports — the module is self-contained, so the host only needs
 * to call exports and read results.
 *
 * Deliberately simple over fast: the point is to be small enough to
 * run inside the emulated guest, not to be a production runtime. The
 * module is trusted (it comes out of moonc), so there is no
 * validation pass.
 */
#ifndef WASM_H
#define WASM_H

#include <stddef.h>
#include <stdint.h>

typedef struct {
  uint32_t nparams, nresults;
  uint8_t *params;  /* value types, unused except for arity */
  uint8_t *results;
} WasmType;

typedef struct {
  uint32_t type_idx;
  const uint8_t *body;     /* first byte after the locals declaration */
  const uint8_t *body_end;
  uint32_t nlocals;        /* declared locals, excluding parameters */
  /* Control-flow map, indexed by offset within the function body:
   * for every block/loop/if opcode, where its `else` and `end` are.
   * Filled in lazily the first time the function is entered. */
  uint32_t *else_at;
  uint32_t *end_at;
  int mapped;
} WasmFunc;

typedef struct {
  uint64_t value;
  uint8_t type;
  uint8_t mutable_;
} WasmGlobal;

typedef struct {
  char *name;
  uint32_t func_idx;
} WasmExport;

typedef struct {
  const uint8_t *bytes;   /* the module image, borrowed */
  size_t size;

  WasmType *types;
  uint32_t ntypes;
  WasmFunc *funcs;
  uint32_t nfuncs;
  WasmGlobal *globals;
  uint32_t nglobals;
  WasmExport *exports;
  uint32_t nexports;
  uint32_t *table;        /* function indices for call_indirect */
  uint32_t table_size;

  uint8_t *mem;
  uint32_t mem_pages;
  uint32_t mem_max_pages;

  int has_start;
  uint32_t start_func;

  /* Shared execution pools. Call frames take slices of these rather
   * than putting operands, locals and labels on the C stack: the
   * interpreter recurses for wasm calls, and the guest this is meant
   * to run inside has a small fixed stack (nommu Linux). */
  uint64_t *vstack;
  uint32_t vstack_size, vsp;
  uint64_t *locals_pool;
  uint32_t locals_size, locals_sp;
  void *label_pool;
  uint32_t label_size, label_sp;
  uint32_t depth, max_depth;

  const char *error;      /* set when a call traps */
} WasmModule;

/* Parse `bytes` (borrowed, must outlive the module), apply data
 * segments and run the start function. Returns 0 on success. */
int wasm_load(WasmModule *m, const uint8_t *bytes, size_t size);

void wasm_free(WasmModule *m);

/* Look up an exported function; returns -1 when absent. */
int wasm_export(WasmModule *m, const char *name);

/* Call function `idx` with `nargs` arguments. Results are written to
 * `results` (up to `max_results`); returns the number produced, or -1
 * on a trap (m->error explains). */
int wasm_call(WasmModule *m, uint32_t idx, const uint64_t *args,
              uint32_t nargs, uint64_t *results, uint32_t max_results);

#endif /* WASM_H */
