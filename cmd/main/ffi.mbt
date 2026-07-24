///|
/// Native host bindings (Linux/POSIX): file reading, raw terminal I/O,
/// CLI arguments (via /proc/self/cmdline), process exit.

///|
extern "c" fn rv_file_size(path : Bytes) -> Int = "rv_file_size"

///|
extern "c" fn rv_read_into(path : Bytes, buf : Bytes) -> Int = "rv_read_into"

///|
extern "c" fn rv_put_byte(b : Int) = "rv_put_byte"

///|
extern "c" fn rv_get_byte() -> Int = "rv_get_byte"

///|
extern "c" fn rv_term_raw(enable : Int) = "rv_term_raw"

///|
extern "c" fn rv_exit(code : Int) = "rv_exit"

///|
fn string_to_c(path : String) -> Bytes {
  // encode as UTF-8 (ASCII paths pass through unchanged)
  let buf : Array[Byte] = []
  for c in path {
    let cp = c.to_int()
    if cp < 0x80 {
      buf.push(cp.to_byte())
    } else if cp < 0x800 {
      buf.push((0xC0 | (cp >> 6)).to_byte())
      buf.push((0x80 | (cp & 0x3F)).to_byte())
    } else if cp < 0x10000 {
      buf.push((0xE0 | (cp >> 12)).to_byte())
      buf.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
      buf.push((0x80 | (cp & 0x3F)).to_byte())
    } else {
      buf.push((0xF0 | (cp >> 18)).to_byte())
      buf.push((0x80 | ((cp >> 12) & 0x3F)).to_byte())
      buf.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
      buf.push((0x80 | (cp & 0x3F)).to_byte())
    }
  }
  Bytes::from_array(buf)
}

///|
fn read_file(path : String) -> Bytes? {
  let cpath = string_to_c(path)
  let size = rv_file_size(cpath)
  if size < 0 {
    return None
  }
  let buf = Bytes::make(size, 0)
  if rv_read_into(cpath, buf) != size {
    return None
  }
  Some(buf)
}

///|
fn put_byte(b : Int) -> Unit {
  rv_put_byte(b)
}

///|
fn get_byte() -> Int {
  rv_get_byte()
}

///|
fn term_raw_begin() -> Unit {
  rv_term_raw(1)
}

///|
fn term_raw_end() -> Unit {
  rv_term_raw(0)
}

///|
fn exit_process(code : Int) -> Unit {
  rv_exit(code)
}

///|
/// argv from /proc/self/cmdline (NUL-separated).
fn cli_args() -> Array[String] {
  let out : Array[String] = []
  match read_file("/proc/self/cmdline") {
    Some(raw) => {
      let cur = StringBuilder()
      let mut has = false
      for i in 0..<raw.length() {
        let b = raw[i].to_int()
        if b == 0 {
          if has {
            out.push(cur.to_string())
          }
          cur.reset()
          has = false
        } else {
          // treat as latin-1; paths and flags are expected to be ASCII
          cur.write_char(b.unsafe_to_char())
          has = true
        }
      }
      if has {
        out.push(cur.to_string())
      }
    }
    None => ()
  }
  out
}
