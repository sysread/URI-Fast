#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "ppport.h"
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

