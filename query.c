#include <stdlib.h>
#include <stdio.h>
#include <string.h>

typedef enum {
  KEY   = 1,
  PARAM = 2,
  DONE  = 3,
} uri_query_token_type_t;

typedef struct {
  uri_query_token_type_t type;
  char *key;   size_t key_length;
  char *value; size_t value_length; // only present when type=PARAM
} uri_query_token_t;

typedef struct {
  char    separator[4];
  size_t  length;
  size_t  cursor;
  char   *source;
} uri_query_scanner_t;

void query_scanner_init(
    uri_query_scanner_t *scanner,
    char *source,
    size_t length
  )
{
  scanner->source = source;
  scanner->length = length;
  scanner->cursor = 0;

  scanner->separator[0] = '&';
  scanner->separator[1] = ';';
  scanner->separator[2] = '=';
  scanner->separator[3] = '\0';
}

int query_scanner_done(uri_query_scanner_t *scanner) {
  return scanner->cursor >= scanner->length;
}

/*
 * Fills the token struct with the next token information. Does not decode
 * any values.
 */
void query_scanner_next(uri_query_scanner_t *scanner, uri_query_token_t *token) {
  size_t brk;

SCAN_KEY:
  if (scanner->cursor >= scanner->length) {
    token->key   = NULL; token->key_length   = 0;
    token->value = NULL; token->value_length = 0;
    token->type  = DONE;
    return;
  }

  // Scan to end of token
  brk = strcspn(&scanner->source[ scanner->cursor ], scanner->separator);

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
    brk = strcspn(&scanner->source[ scanner->cursor ], scanner->separator);

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
