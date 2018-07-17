#include <stdlib.h>
#include "fast.h"

typedef struct {
  size_t chunk;
  size_t allocated;
  size_t length;
  char *string;
} uri_str_t;

inline
size_t str_len(uri_str_t *str) {
  return str->length;
}

inline
const char *str_get(uri_str_t *str) {
  return (const char*)str->string;
}

void str_set(pTHX_ uri_str_t *str, const char *value, size_t len) {
  size_t allocate = str->chunk * (((len + 1) / str->chunk) + 1);

  if (str->string == NULL) {
    Newx(str->string, allocate, char);
    str->allocated = allocate;
  }
  else if (len > str->allocated) {
    Renew(str->string, allocate, char);
    str->allocated = allocate;
  }

  if (value == NULL) {
    Zero(str->string, len + 1, char);
    str->length = 0;
  }
  else {
    Copy(value, str->string, len, char);
    str->string[len] = '\0';
    str->length = len;
  }
}

void str_append(pTHX_ uri_str_t *str, const char *value, size_t len) {
  if (str->string == NULL) {
    str_set(aTHX_ str, value, len);
    return;
  }

  if (value != NULL) {
    size_t allocate = str->chunk * (((str->length + len + 1) / str->chunk) + 1);

    if (allocate != str->allocated) {
      Renew(str->string, allocate, char);
      str->allocated = allocate;
    }

    Copy(value, &str->string[str->length], len, char);
    str->string[str->length + len] = '\0';
    str->length += len;
  }
}

inline
void str_clear(pTHX_ uri_str_t *str) {
  str_set(aTHX_ str, NULL, 0);
}

uri_str_t* str_new(pTHX_ size_t alloc_size) {
  uri_str_t *str;
  Newx(str, 1, uri_str_t);
  str->chunk = alloc_size;
  str->allocated = 0;
  str->length = 0;
  str->string = NULL;
  return str;
}

inline
void str_free(pTHX_ uri_str_t *str) {
  if (str->string != NULL) {
    Safefree(str->string);
  }

  Safefree(str);
}
