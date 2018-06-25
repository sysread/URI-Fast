#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include "../ppport.h"
#include "defs.c"

/*
 * Token type
 */
typedef enum {
  KEY   = 1, // key-only, e.g. ?foo&bar
  PARAM = 2, // key-value pair, e.g. ?foo=bar
  DONE  = 3, // scanner reached end of query
} uri_query_token_type_t;

/*
 * Token
 */
typedef struct {
  uri_query_token_type_t type;      // always present
  char *key;   size_t key_length;   // present when type=KEY|PARAM
  char *value; size_t value_length; // present when type=PARAM
} uri_query_token_t;

/*
 * Scanner
 */
typedef struct {
  size_t  length;
  size_t  cursor;
  char   *source;
} uri_query_scanner_t;

/*
 * Initializes a scanner struct for the given source char*, which will scan up
 * to length bytes.
 */
void query_scanner_init(uri_query_scanner_t *scanner, char *source, size_t length) {
  scanner->source = source;
  scanner->length = length;
  scanner->cursor = 0;
}

/*
 * Returns 1 when the cursor has reached the end of the source char*.
 */
int query_scanner_done(uri_query_scanner_t *scanner) {
  return scanner->cursor >= scanner->length;
}

/*
 * Fills the token struct with the next token information. Does not decode
 * any values.
 */
void query_scanner_next(uri_query_scanner_t *scanner, uri_query_token_t *token) {
  size_t brk;
  const char sep[4] = {'&', ';', '=', '\0'};

SCAN_KEY:
  if (query_scanner_done(scanner)) {
    token->key   = NULL; token->key_length   = 0;
    token->value = NULL; token->value_length = 0;
    token->type  = DONE;
    return;
  }

  // Scan to end of token
  brk = strcspn(&scanner->source[ scanner->cursor ], sep);

  // Set key members in token struct
  token->key = &scanner->source[ scanner->cursor ];
  token->key_length = brk;

  // Move cursor to end of token
  scanner->cursor += brk;

  // If there is an associate value, add it to the token
  if (scanner->source[ scanner->cursor ] == '=') {
    // Advance past '='
    ++scanner->cursor;

    // Find the end of the value
    brk = strcspn(&scanner->source[ scanner->cursor ], sep);

    // Set the value and token type
    token->value = &scanner->source[ scanner->cursor ];
    token->value_length = brk;
    token->type = PARAM;

    // Move cursor to the end of the value, eating the separator terminating it
    scanner->cursor += brk + 1;
  }
  // No value assigned to this key
  else {
    token->type = KEY;
    ++scanner->cursor; // advance past terminating separator
  }

  // No key was found; try again
  if (token->key_length == 0) {
    goto SCAN_KEY;
  }

  return;
}

/*
 * perlguts functions
 */
static
SV* get_query_keys(pTHX_ SV* uri) {
  char* query = URI_MEMBER(uri, query);
  size_t klen, qlen = strlen(query);
  HV* out = newHV();
  uri_query_scanner_t scanner;
  uri_query_token_t token;

  query_scanner_init(&scanner, query, qlen);

  while (!query_scanner_done(&scanner)) {
    query_scanner_next(&scanner, &token);
    if (token.type == DONE) continue;
    char key[token.key_length];
    klen = uri_decode(token.key, token.key_length, key);
    hv_store(out, key, -klen, &PL_sv_undef, 0);
  }

  return newRV_noinc((SV*) out);
}

static
SV* query_hash(pTHX_ SV* uri) {
  SV *tmp, **refval;
  AV *arr;
  HV *out = newHV();
  char* query = URI_MEMBER(uri, query);
  size_t qlen = strlen(query), klen, vlen;
  uri_query_scanner_t scanner;
  uri_query_token_t token;

  query_scanner_init(&scanner, query, qlen);

  while (!query_scanner_done(&scanner)) {
    query_scanner_next(&scanner, &token);
    if (token.type == DONE) continue;

    // Get decoded key
    char key[token.key_length + 1];
    klen = uri_decode(token.key, token.key_length, key);

    // Values are stored in an array; this block is the rough equivalent of:
    //   $out{$key} = [] unless exists $out{$key};
    if (!hv_exists(out, key, klen)) {
      arr = newAV();
      hv_store(out, key, -klen, newRV_noinc((SV*) arr), 0);
    }
    else {
      refval = hv_fetch(out, key, -klen, 0);
      if (refval == NULL) croak("query_hash: something went wrong");
      arr = (AV*) SvRV(*refval);
    }

    // Get decoded value if there is one
    if (token.type == PARAM) {
      char val[token.value_length + 1];
      vlen = uri_decode(token.value, token.value_length, val);
      tmp = newSVpv(val, vlen);
      sv_utf8_decode(tmp);
      av_push(arr, tmp);
    }
  }

  return newRV_noinc((SV*) out);
}

static
void update_query_keyset(pTHX_ SV *uri, SV *sv_key_set, char separator) {
  HE     *ent;
  HV     *keys, *enc_keys;
  I32    iterlen, i, klen;
  SV     *val, **refval;
  bool   copy;
  char   *key, *query = URI_MEMBER(uri, query);
  char   dest[URI_SIZE_query];
  int    is_iri = URI_MEMBER(uri, is_iri);
  size_t off = 0, qlen = strlen(query);

  uri_query_scanner_t scanner;
  uri_query_token_t   token;

  // Validate reference parameters
  if (!SvROK(sv_key_set) || SvTYPE(SvRV(sv_key_set)) != SVt_PVHV) {
    croak("set_query_keys: expected hash ref");
  }

  // Dereference key set hash
  keys = (HV*) SvRV(sv_key_set);

  // Create new HV with all keys uri-encoded
  enc_keys = newHV();
  iterlen = hv_iterinit(keys);

  for (i = 0; i < iterlen; ++i) {
    ent = hv_iternext(keys);
    key = hv_iterkey(ent, &klen);
    val = hv_iterval(keys, ent);

    SvGETMAGIC(val);

    char enc_key[(3 * klen) + 1];
    klen = uri_encode(key, klen, enc_key, URI_QUERY_TOK_CHARS, URI_QUERY_TOK_CHARS_LEN, is_iri);

    hv_store(enc_keys, enc_key, klen * (is_iri ? -1 : 1), val, 0);
  }

  // Begin building the new query string from the existing one. As each key is
  // encountered in the query string, exclude ones with a falsish value in the
  // hash and keep the ones with a truish value. Any not present in the hash
  // are kept unchanged.
  query_scanner_init(&scanner, query, qlen);

  while (!query_scanner_done(&scanner)) {
    query_scanner_next(&scanner, &token);
    if (token.type == DONE) continue;

    // Use the encrypted keys hash to decide whether to copy this key (and
    // value if present) over to dest. If the key exists, skip. It will be
    // added to the filtered query string last.
    copy = 1;
    if (hv_exists(enc_keys, token.key, token.key_length * (is_iri ? -1 : 1))) {
      refval = hv_fetch(enc_keys, token.key, token.key_length * (is_iri ? -1 : 1), 0);
      // NULL shouldn't be possible since this is guarded with hv_exists, but
      // perlguts, amirite?
      copy = refval == NULL || SvTRUE(*refval);
    }

    if (copy) {
      if (off > 0) {
        dest[off++] = separator;
      }

      strncpy(&dest[off], token.key, token.key_length);
      off += token.key_length;

      if (token.type == PARAM) {
        dest[off++] = '=';
        strncpy(&dest[off], token.value, token.value_length);
        off += token.value_length;
      }
    }
  }

  // Walk through the encoded-key hash, adding remaining keys.
  iterlen = hv_iterinit(enc_keys);

  for (i = 0; i < iterlen; ++i) {
    ent = hv_iternext(enc_keys);
    key = hv_iterkey(ent, &klen);
    val = hv_iterval(enc_keys, ent);

    if (SvTRUE(val)) {
      // Add separator if the new query string is not empty
      if (off > 0) {
        dest[off++] = separator;
      }

      strncpy(&dest[off], key, klen);
      off += klen;
    }
  }

  dest[off++] = '\0';

  memset(&(URI_MEMBER(uri, query)), '\0', sizeof(uri_query_t));
  strncpy(URI_MEMBER(uri, query), dest, off);
}

static
void set_param(pTHX_ SV* uri, SV* sv_key, SV* sv_values, char separator) {
  int    is_iri = URI_MEMBER(uri, is_iri);
  char   *key, *strval, *query = URI_MEMBER(uri, query);
  size_t qlen = strlen(query), klen, vlen, slen, av_idx, i = 0, brk = 0, off = 0;
  char   dest[URI_SIZE_query];
  AV     *av_values;
  SV     **refval;
  uri_query_scanner_t scanner;
  uri_query_token_t token;

  // Build encoded key string
  SvGETMAGIC(sv_key);
  key = SvPV_nomg(sv_key, klen);
  char enc_key[(3 * klen) + 1];
  klen = uri_encode(key, strlen(key), enc_key, URI_QUERY_TOK_CHARS, URI_QUERY_TOK_CHARS_LEN, is_iri);

  // Get array of values to set
  SvGETMAGIC(sv_values);
  if (!SvROK(sv_values) || SvTYPE(SvRV(sv_values)) != SVt_PVAV) {
    croak("set_param: expected array of values");
  }

  av_values = (AV*) SvRV(sv_values);
  av_idx = av_top_index(av_values);

  // Begin building the new query string from the existing one, skipping
  // keys (and their values, if any) matching sv_key.
  query_scanner_init(&scanner, query, qlen);

  while (!query_scanner_done(&scanner)) {
    query_scanner_next(&scanner, &token);
    if (token.type == DONE) continue;

    // The key does not match the key being set
    if (strncmp(enc_key, token.key, maxnum(klen, token.key_length)) != 0) {
      // Add separator if this is not the first key being written
      if (off > 0) {
        dest[off++] = separator;
      }

      // Write the key to the buffer
      strncpy(&dest[off], token.key, token.key_length);
      off += token.key_length;

      // The key has a value
      if (token.type == PARAM) {
        dest[off++] = '=';

        // If the value's length is 0, it was parsed from "key=", so the value
        // is not written after the '=' is added above.
        if (token.value_length > 0) {
          // Otherwise, write the value to the buffer
          strncpy(&dest[off], token.value, token.value_length);
          off += token.value_length;
        }
      }
    }
  }

  // Add the new values to the query
  for (i = 0; i <= av_idx; ++i) {
    // Fetch next value from the array
    refval = av_fetch(av_values, (SSize_t) i, 0);
    if (refval == NULL) break;
    if (!SvOK(*refval)) break;

    // Break out after hitting the limit of the query slot
    if (off == URI_SIZE_query) break;

    // Add separator if needed to separate pairs
    if (off > 0) dest[off++] = separator;

    // Break out early if this key would overflow the struct member
    if (off + klen + 1 > URI_SIZE_query) break;

    // Copy key over
    strncpy(&dest[off], enc_key, klen);
    off += klen;

    dest[off++] = '=';

    // Copy value over
    SvGETMAGIC(*refval);
    strval = SvPV_nomg(*refval, slen);

    vlen = uri_encode(strval, slen, &dest[off], URI_QUERY_TOK_CHARS, URI_QUERY_TOK_CHARS_LEN, is_iri);
    off += vlen;
  }

  memset(&(URI_MEMBER(uri, query)), '\0', sizeof(uri_query_t));
  strncpy(URI_MEMBER(uri, query), dest, off);
}

