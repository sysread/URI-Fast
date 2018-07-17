#define PERL_NO_GET_CONTEXT

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

#include "fast.h"
#include "strnspn.c"
#include "query.c"
#include "urlencode.c"
//#include "str.c"

/*
 * Strings
 */
typedef struct {
  size_t chunk;
  size_t allocated;
  size_t length;
  char *string;
} uri_str_t;

static inline
size_t str_len(uri_str_t *str) {
  return str->length;
}

static inline
const char *str_get(uri_str_t *str) {
  return (const char*)str->string;
}

static
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

static
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

static inline
void str_clear(pTHX_ uri_str_t *str) {
  str_set(aTHX_ str, NULL, 0);
}

static
uri_str_t* str_new(pTHX_ size_t alloc_size) {
  uri_str_t *str;
  Newx(str, 1, uri_str_t);
  str->chunk = alloc_size;
  str->allocated = 0;
  str->length = 0;
  str->string = NULL;
  return str;
}

static inline
void str_free(pTHX_ uri_str_t *str) {
  if (str->string != NULL) {
    Safefree(str->string);
  }

  Safefree(str);
}

// returns true for an ASCII whitespace char
static inline
bool my_isspace(const char c) {
  switch (c) {
    case ' ':  case '\t':
    case '\r': case '\n':
    case '\f': case '\v':
      return 1;
    default:
      return 0;
  }
}

// min of two numbers
static inline
size_t minnum(size_t x, size_t y) {
  return x <= y ? x : y;
}

// max of two numbers
static inline
size_t maxnum(size_t x, size_t y) {
  return x >= y ? x : y;
}

/*
 * Internal API
 */
typedef char uri_scheme_t [URI_SIZE_scheme + 1];
typedef char uri_path_t   [URI_SIZE_path + 1];
typedef char uri_query_t  [URI_SIZE_query + 1];
typedef char uri_frag_t   [URI_SIZE_frag + 1];
typedef char uri_usr_t    [URI_SIZE_usr + 1];
typedef char uri_pwd_t    [URI_SIZE_pwd + 1];
typedef char uri_host_t   [URI_SIZE_host + 1];
typedef char uri_port_t   [URI_SIZE_port + 1];
typedef int  uri_is_iri_t;

typedef struct {
  uri_is_iri_t is_iri;
  uri_str_t *scheme;
  uri_str_t *query;
  uri_str_t *path;
  uri_str_t *host;
  uri_str_t *port;
  uri_str_t *frag;
  uri_str_t *usr;
  uri_str_t *pwd;
} uri_t;

/*
 * Clearers
 */
URI_SIMPLE_CLEARER(scheme);
URI_SIMPLE_CLEARER(path);
URI_SIMPLE_CLEARER(query);
URI_SIMPLE_CLEARER(frag);
URI_SIMPLE_CLEARER(usr);
URI_SIMPLE_CLEARER(pwd);
URI_SIMPLE_CLEARER(host);
URI_SIMPLE_CLEARER(port);

static
void clear_auth(pTHX_ SV *uri_obj) {
  clear_usr(aTHX_ uri_obj);
  clear_pwd(aTHX_ uri_obj);
  clear_host(aTHX_ uri_obj);
  clear_port(aTHX_ uri_obj);
}

/*
 * Scans the authorization portion of the URI string
 */
static
void uri_scan_auth(pTHX_ uri_t* uri, const char* auth, const size_t len) {
  size_t idx  = 0;
  size_t brk1 = 0;
  size_t brk2 = 0;
  size_t i;
  unsigned char flag;

  if (len > 0) {
    // Credentials
    brk1 = strncspn(&auth[idx], len - idx, "@");

    if (brk1 > 0 && brk1 != (len - idx)) {
      brk2 = strncspn(&auth[idx], len - idx, ":");

      if (brk2 > 0 && brk2 < brk1) {
        // user
        str_set(aTHX_ uri->usr, &auth[idx], brk2);
        idx += brk2 + 1;

        // password
        str_set(aTHX_ uri->pwd, &auth[idx], brk1 - brk2 - 1);
        idx += brk1 - brk2;
      }
      else {
        // user only
        str_set(aTHX_ uri->usr, &auth[idx], brk1);
        idx += brk1 + 1;
      }
    }

    // Location

    // Maybe an IPV6 address
    flag = 0;
    if (auth[idx] == '[') {
      brk1 = strncspn(&auth[idx], len - idx, "]");

      if (auth[idx + brk1] == ']') {
        // Copy, including the square brackets
        str_set(aTHX_ uri->host, &auth[idx], brk1 + 1);
        idx += brk1 + 1;
        flag = 1;
      }
    }

    if (flag == 0) {
      brk1 = strncspn(&auth[idx], len - idx, ":");

      if (brk1 > 0) {
        str_set(aTHX_ uri->host, &auth[idx], brk1);
        idx += brk1;
      }
    }

    if (auth[idx] == ':') {
      ++idx;
      str_set(aTHX_ uri->port, &auth[idx], len - idx);
    }
  }
}

/*
 * Scans a URI string and populates the uri_t struct.
 *
 * Correct:
 *   scheme:[//[usr[:pwd]@]host[:port]]path[?query][#fragment]
 *
 * Incorrect but supported:
 *   /path[?query][#fragment]
 *
 */
static
void uri_scan(pTHX_ uri_t *uri, const char *src, size_t len) {
  size_t idx = 0;
  size_t brk;
  size_t i;

  while (my_isspace(src[idx]) == 1)     ++idx; // Trim leading whitespace
  while (my_isspace(src[len - 1]) == 1) --len; // Trim trailing whitespace

  // Scheme
  brk = strncspn(&src[idx], len - idx, ":/@?#");

  if (brk > 0 && src[idx + brk] == ':') {
    str_set(aTHX_ uri->scheme, &src[idx], brk);
    idx += brk + 1;

    // Authority section following scheme must be separated by //
    if (idx + 1 < len && src[idx] == '/' && src[idx + 1] == '/') {
      idx += 2;
    }
  }

  // Authority
  brk = strncspn(&src[idx], len - idx, "/?#");
  uri_scan_auth(aTHX_ uri, &src[idx], brk);

  if (brk > 0) {
    idx += brk;
  }

  // path
  brk = strncspn(&src[idx], len - idx, "?#");
  if (brk > 0) {
    str_set(aTHX_ uri->path, &src[idx], brk);
    idx += brk;
  }

  // query
  if (src[idx] == '?') {
    ++idx; // skip past ?
    brk = strncspn(&src[idx], len - idx, "#");
    if (brk > 0) {
      str_set(aTHX_ uri->query, &src[idx], brk);
      idx += brk;
    }
  }

  // fragment
  if (src[idx] == '#') {
    ++idx; // skip past #
    brk = len - idx;
    if (brk > 0) {
      str_set(aTHX_ uri->frag, &src[idx], brk);
    }
  }
}

/*
 * Perl API
 */

/*
 * Getters
 */

// Raw getters
URI_RAW_GETTER(scheme);
URI_RAW_GETTER(usr);
URI_RAW_GETTER(pwd);
URI_RAW_GETTER(host);
URI_RAW_GETTER(port);
URI_RAW_GETTER(path);
URI_RAW_GETTER(query);
URI_RAW_GETTER(frag);

static
SV* get_raw_auth(pTHX_ SV *uri_obj) {
  uri_t *uri = URI(uri_obj);
  SV *out = newSVpvn("", 0);

  if (uri->is_iri) {
    SvUTF8_on(out);
  }

  if (str_len(uri->usr) > 0) {
    if (str_len(uri->pwd) > 0) {
      sv_catpvn(out, str_get(uri->usr), str_len(uri->usr));
      sv_catpvn(out, ":", 1);
      sv_catpvn(out, str_get(uri->pwd), str_len(uri->pwd));
      sv_catpvn(out, "@", 1);
    } else {
      sv_catpvn(out, str_get(uri->usr), str_len(uri->usr));
      sv_catpvn(out, "@", 1);
    }
  }

  if (str_len(uri->host) > 0) {
    if (str_len(uri->port) > 0) {
      sv_catpvn(out, str_get(uri->host), str_len(uri->host));
      sv_catpvn(out, ":", 1);
      sv_catpvn(out, str_get(uri->port), str_len(uri->port));
    } else {
      sv_catpvn(out, str_get(uri->host), str_len(uri->host));
    }
  }

  return out;
}

// Decoding getters
URI_SIMPLE_GETTER(scheme);
URI_SIMPLE_GETTER(usr);
URI_SIMPLE_GETTER(pwd);
URI_SIMPLE_GETTER(host);
URI_SIMPLE_GETTER(port);
URI_SIMPLE_GETTER(frag);
URI_COMPOUND_GETTER(path);
URI_COMPOUND_GETTER(query);

static
SV* get_auth(pTHX_ SV *uri_obj) {
  uri_t *uri = URI(uri_obj);
  SV *out = newSVpvn("", 0);

  if (uri->is_iri) {
    SvUTF8_on(out);
  }

  if (str_len(uri->usr) > 0) {
    if (str_len(uri->pwd) > 0) {
      sv_catsv_nomg(out, sv_2mortal(get_usr(aTHX_ uri_obj)));
      sv_catpvn(out, ":", 1);
      sv_catsv_nomg(out, sv_2mortal(get_pwd(aTHX_ uri_obj)));
      sv_catpvn(out, "@", 1);
    } else {
      sv_catsv_nomg(out, sv_2mortal(get_usr(aTHX_ uri_obj)));
      sv_catpvn(out, "@", 1);
    }
  }

  if (str_len(uri->host) > 0) {
    if (str_len(uri->port) > 0) {
      sv_catsv_nomg(out, sv_2mortal(get_host(aTHX_ uri_obj)));
      sv_catpvn(out, ":", 1);
      sv_catsv_nomg(out, sv_2mortal(get_port(aTHX_ uri_obj)));
    } else {
      sv_catsv_nomg(out, sv_2mortal(get_host(aTHX_ uri_obj)));
    }
  }

  return out;
}

static
SV* split_path(pTHX_ SV* uri) {
  size_t len, segment_len, brk, idx = 0;
  AV* arr = newAV();
  SV* tmp;

  const char *str = str_get(URI_MEMBER(uri, path));
  len = str_len(URI_MEMBER(uri, path));

  if (len > 0) {
    if (str[0] == '/') {
      ++idx; // skip past leading /
    }

    while (idx < len) {
      // Find the next separator
      brk = strcspn(&str[idx], "/");

      // Decode the segment
      char segment[brk + 1];
      segment_len = uri_decode(&str[idx], brk, segment, "");

      // Push new SV to AV
      tmp = newSVpvn(segment, segment_len);
      sv_utf8_decode(tmp);
      av_push(arr, tmp);

      idx += brk + 1;
    }
  }

  return newRV_noinc((SV*) arr);
}

static
SV* get_query_keys(pTHX_ SV* uri) {
  const char *query = str_get(URI_MEMBER(uri, query));
  size_t klen, qlen = str_len(URI_MEMBER(uri, query));
  HV* out = newHV();
  uri_query_scanner_t scanner;
  uri_query_token_t token;

  query_scanner_init(&scanner, query, qlen);

  while (!query_scanner_done(&scanner)) {
    query_scanner_next(&scanner, &token);
    if (token.type == DONE) continue;
    char key[token.key_length];
    klen = uri_decode(token.key, token.key_length, key, "");
    hv_store(out, key, -klen, &PL_sv_undef, 0);
  }

  return newRV_noinc((SV*) out);
}

static
SV* query_hash(pTHX_ SV* uri) {
  SV *tmp, **refval;
  AV *arr;
  HV *out = newHV();
  const char *query = str_get(URI_MEMBER(uri, query));
  size_t qlen = str_len(URI_MEMBER(uri, query)), klen, vlen;
  uri_query_scanner_t scanner;
  uri_query_token_t token;

  query_scanner_init(&scanner, query, qlen);

  while (!query_scanner_done(&scanner)) {
    query_scanner_next(&scanner, &token);
    if (token.type == DONE) continue;

    // Get decoded key
    char key[token.key_length + 1];
    klen = uri_decode(token.key, token.key_length, key, "");

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
      vlen = uri_decode(token.value, token.value_length, val, "");
      tmp = newSVpvn(val, vlen);
      sv_utf8_decode(tmp);
      av_push(arr, tmp);
    }
  }

  return newRV_noinc((SV*) out);
}

static
SV* get_param(pTHX_ SV* uri, SV* sv_key) {
  int is_iri = URI_MEMBER(uri, is_iri);
  const char *query = str_get(URI_MEMBER(uri, query));
  const char *key;
  size_t qlen = str_len(URI_MEMBER(uri, query)), klen, vlen, elen;
  uri_query_scanner_t scanner;
  uri_query_token_t token;
  AV* out = newAV();
  SV* value;

  // Read key to search
  if (!SvTRUE(sv_key)) {
    croak("get_param: expected key to search");
  }
  else {
    // Copy input string *before* calling DO_UTF8() in case the SV is an object
    // with string overloading, which may trigger the utf8 flag.
    key = SvPV_const(sv_key, klen);

    if (!DO_UTF8(sv_key)) {
      sv_key = sv_2mortal(newSVpvn(key, klen));
      sv_utf8_encode(sv_key);
      key = SvPV_const(sv_key, klen);
    }
  }

  char enc_key[(klen * 3) + 2];
  elen = uri_encode(key, klen, enc_key, ":@?/", is_iri);

  query_scanner_init(&scanner, query, qlen);

  while (!query_scanner_done(&scanner)) {
    query_scanner_next(&scanner, &token);
    if (token.type == DONE) continue;

    if (strncmp(enc_key, token.key, maxnum(elen, token.key_length)) == 0) {
      if (token.type == PARAM) {
        char val[token.value_length + 1];
        vlen = uri_decode(token.value, token.value_length, val, "");
        value = newSVpvn(val, vlen);
        sv_utf8_decode(value);
        av_push(out, value);
      }
      else {
        av_push(out, newSV(0));
      }
    }
  }

  return newRV_noinc((SV*) out);
}

/*
 * Setters
 */
URI_SIMPLE_SETTER(scheme, "");
URI_SIMPLE_SETTER(path,   URI_CHARS_PATH);
URI_SIMPLE_SETTER(query,  URI_CHARS_QUERY);
URI_SIMPLE_SETTER(frag,   URI_CHARS_FRAG);
URI_SIMPLE_SETTER(usr,    URI_CHARS_USER);
URI_SIMPLE_SETTER(pwd,    URI_CHARS_USER);
URI_SIMPLE_SETTER(host,   URI_CHARS_HOST);

static
void set_port(pTHX_ SV *uri_obj, SV *sv_value) {
  if (!SvTRUE(sv_value)) {
    str_clear(aTHX_ URI_MEMBER(uri_obj, port));
    return;
  }

  size_t vlen, i;
  const char *value = SvPV_const(sv_value, vlen);
  str_set(aTHX_ URI_MEMBER(uri_obj, port), value, vlen);
}

static
void set_auth(pTHX_ SV *uri_obj, SV *sv_value) {
  str_clear(aTHX_ URI_MEMBER(uri_obj, usr));
  str_clear(aTHX_ URI_MEMBER(uri_obj, pwd));
  str_clear(aTHX_ URI_MEMBER(uri_obj, host));
  str_clear(aTHX_ URI_MEMBER(uri_obj, port));

  if (SvTRUE(sv_value)) {
    size_t vlen;
    const char *value = SvPV_const(sv_value, vlen);

    // auth isn't stored as an individual field, so encode to local array and rescan
    char auth[URI_SIZE_auth];
    size_t len = uri_encode(value, vlen, (char*) &auth, URI_CHARS_AUTH, URI_MEMBER(uri_obj, is_iri));

    uri_scan_auth(aTHX_ URI(uri_obj), auth, len);
  }
}

static
void set_path_array(pTHX_ SV *uri_obj, SV *sv_path) {
  SV **refval, *tmp;
  AV *av_path;
  size_t i, av_idx, seg_len;
  const char *seg;
  uri_str_t *path = URI_MEMBER(uri_obj, path);

  str_clear(aTHX_ path);

  if (!SvTRUE(sv_path)) {
    return;
  }

  // Inspect input array
  av_path = (AV*) SvRV(sv_path);
  av_idx  = av_top_index(av_path);

  // Build the new path
  for (i = 0; i <= av_idx; ++i) {
    // Add separator. If the next value fetched from the array is invalid, it
    // just gets an empty segment.
    str_append(aTHX_ path, "/", 1);

    // Fetch next segment
    refval = av_fetch(av_path, (SSize_t) i, 0);
    if (refval == NULL) continue;
    if (!SvTRUE(*refval)) continue;

    // Copy value over
    if (SvTRUE(*refval)) {
      seg = SvPV_nomg_const(*refval, seg_len);

      // Convert octets to utf8 if necessary
      if (!DO_UTF8(*refval)) {
        tmp = sv_2mortal(newSVpvn(seg, seg_len));
        sv_utf8_encode(tmp);
        seg = SvPV_const(tmp, seg_len);
      }

      char out[seg_len * 3];
      size_t out_len = uri_encode(seg, seg_len, out, URI_CHARS_PATH_SEGMENT, URI_MEMBER(uri_obj, is_iri));

      str_append(aTHX_ path, out, out_len);
    }
  }
}

static
void update_query_keyset(pTHX_ SV *uri, SV *sv_key_set, SV *sv_separator) {
  int    is_iri = URI_MEMBER(uri, is_iri);
  HE     *ent;
  HV     *keys, *enc_keys;
  I32    iterlen, i, klen;
  SV     *val, **refval;
  bool   copy;
  char   *key;
  size_t off = 0;
  uri_str_t *query = URI_MEMBER(uri, query);
  uri_str_t *dest  = str_new(aTHX_ URI_SIZE_query);

  size_t slen = 1;
  const char *separator = SvTRUE(sv_separator) ? SvPV_const(sv_separator, slen) : "&";

  uri_query_scanner_t scanner;
  uri_query_token_t   token;

  // Validate reference parameters
  SvGETMAGIC(sv_key_set);

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
    klen = uri_encode(key, klen, enc_key, ":@?/", is_iri);

    hv_store(enc_keys, enc_key, klen * (is_iri ? -1 : 1), val, 0);
  }

  // Begin building the new query string from the existing one. As each key is
  // encountered in the query string, exclude ones with a falsish value in the
  // hash and keep the ones with a truish value. Any not present in the hash
  // are kept unchanged.
  query_scanner_init(&scanner, str_get(query), str_len(query));

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
        str_append(aTHX_ dest, separator, slen);
        off += slen;
      }

      str_append(aTHX_ dest, token.key, token.key_length);
      off += token.key_length;

      if (token.type == PARAM) {
        str_append(aTHX_ dest, "=", 1);
        str_append(aTHX_ dest, token.value, token.value_length);
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
        str_append(aTHX_ dest, separator, slen);
        off += slen;
      }

      str_append(aTHX_ dest, key, klen);
      off += klen;
    }
  }

  str_free(aTHX_ query);
  URI_MEMBER(uri, query) = dest;
}

static
void set_param(pTHX_ SV *uri, SV *sv_key, SV *sv_values, SV *sv_separator) {
  int is_iri = URI_MEMBER(uri, is_iri);
  char *strval;
  size_t vlen, reflen, av_idx, i = 0, off = 0;
  AV *av_values;
  SV **refval;
  uri_str_t *query = URI_MEMBER(uri, query);
  uri_str_t *dest = str_new(aTHX_ URI_SIZE_query);
  uri_query_scanner_t scanner;
  uri_query_token_t token;

  size_t slen = 1;
  const char *separator = SvTRUE(sv_separator) ? SvPV_const(sv_separator, slen) : "&";

  // Build encoded key string
  if (!SvTRUE(sv_key)) {
    croak("set_param: expected key");
  }

  size_t klen;
  const char *key = SvPV_const(sv_key, klen);
  char enc_key[(3 * klen) + 1];
  klen = uri_encode(key, strlen(key), enc_key, ":@?/", is_iri);

  // Get array of values to set
  SvGETMAGIC(sv_values);

  if (!SvROK(sv_values) || SvTYPE(SvRV(sv_values)) != SVt_PVAV) {
    croak("set_param: expected array of values");
  }

  av_values = (AV*) SvRV(sv_values);
  av_idx = av_top_index(av_values);

  // Begin building the new query string from the existing one, skipping
  // keys (and their values, if any) matching sv_key.
  query_scanner_init(&scanner, str_get(query), str_len(query));

  while (!query_scanner_done(&scanner)) {
    query_scanner_next(&scanner, &token);
    if (token.type == DONE) continue;

    // The key does not match the key being set
    if (strncmp(enc_key, token.key, maxnum(klen, token.key_length)) != 0) {
      // Add separator if this is not the first key being written
      if (off > 0) {
        str_append(aTHX_ dest, separator, slen);
        off += slen;
      }

      // Write the key to the buffer
      str_append(aTHX_ dest, token.key, token.key_length);
      off += token.key_length;

      // The key has a value
      if (token.type == PARAM) {
        str_append(aTHX_ dest, "=", 1);

        // If the value's length is 0, it was parsed from "key=", so the value
        // is not written after the '=' is added above.
        if (token.value_length > 0) {
          // Otherwise, write the value to the buffer
          str_append(aTHX_ dest, token.value, token.value_length);
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
    if (!SvTRUE(*refval)) break;

    // Add separator if needed to separate pairs
    if (off > 0) {
      str_append(aTHX_ dest, separator, slen);
      off += slen;
    }

    // Copy key over
    str_append(aTHX_ dest, enc_key, klen);
    off += klen;

    str_append(aTHX_ dest, "=", 1);

    // Copy value over
    SvGETMAGIC(*refval);
    strval = SvPV_nomg(*refval, reflen);

    char tmp[reflen * 3];
    vlen = uri_encode(strval, reflen, tmp, ":@?/", is_iri);
    str_append(aTHX_ dest, tmp, vlen);
    off += vlen;
  }

  str_free(aTHX_ query);
  URI_MEMBER(uri, query) = dest;
}

/*
 * Other stuff
 */

static
SV* to_string(pTHX_ SV* uri_obj) {
  uri_t *uri = URI(uri_obj);
  SV *out = newSVpvn("", 0);
  SV *auth = get_auth(aTHX_ uri_obj);

  if (uri->is_iri) {
    SvUTF8_on(out);
  }

  if (str_len(uri->scheme) > 0) {
    sv_catpvn(out, str_get(uri->scheme), str_len(uri->scheme));
    sv_catpvn(out, ":", 1);

    if (SvTRUE(auth)) {
      // When the authority section is present, the scheme must be followed by
      // two forward slashes
      sv_catpvn(out, "//", 2);
    }
  }

  if (SvTRUE(auth)) {
    sv_catsv(out, sv_2mortal(auth));

    // When the authority section is present, any path must be separated from
    // the authority section by a forward slash
    if (str_len(uri->path) > 0 && (str_get(uri->path))[0] != '/') {
      sv_catpvn(out, "/", 1);
    }
  }

  sv_catpvn(out, str_get(uri->path), str_len(uri->path));

  if (str_len(uri->query) > 0) {
    sv_catpvn(out, "?", 1);
    sv_catpvn(out, str_get(uri->query), str_len(uri->query));
  }

  if (str_len(uri->frag) > 0) {
    sv_catpvn(out, "#", 1);
    sv_catpvn(out, str_get(uri->frag), str_len(uri->frag));
  }

  return out;
}

static
void explain(pTHX_ SV* uri_obj) {
  printf("scheme: %s\n",  str_get(URI_MEMBER(uri_obj, scheme)));
  printf("auth:\n");
  printf("  -usr: %s\n",  str_get(URI_MEMBER(uri_obj, usr)));
  printf("  -pwd: %s\n",  str_get(URI_MEMBER(uri_obj, pwd)));
  printf("  -host: %s\n", str_get(URI_MEMBER(uri_obj, host)));
  printf("  -port: %s\n", str_get(URI_MEMBER(uri_obj, port)));
  printf("path: %s\n",    str_get(URI_MEMBER(uri_obj, path)));
  printf("query: %s\n",   str_get(URI_MEMBER(uri_obj, query)));
  printf("frag: %s\n",    str_get(URI_MEMBER(uri_obj, frag)));
}

static
void debug(pTHX_ SV* uri_obj) {
  warn("scheme: %s\n",  str_get(URI_MEMBER(uri_obj, scheme)));
  warn("auth:\n");
  warn("  -usr: %s\n",  str_get(URI_MEMBER(uri_obj, usr)));
  warn("  -pwd: %s\n",  str_get(URI_MEMBER(uri_obj, pwd)));
  warn("  -host: %s\n", str_get(URI_MEMBER(uri_obj, host)));
  warn("  -port: %s\n", str_get(URI_MEMBER(uri_obj, port)));
  warn("path: %s\n",    str_get(URI_MEMBER(uri_obj, path)));
  warn("query: %s\n",   str_get(URI_MEMBER(uri_obj, query)));
  warn("frag: %s\n",    str_get(URI_MEMBER(uri_obj, frag)));
}

static
SV* new(pTHX_ const char* class, SV* uri_str, int is_iri) {
  const char* src;
  size_t len;
  uri_t* uri;
  SV*    obj;
  SV*    obj_ref;

  // Initialize the struct
  Newx(uri, 1, uri_t);
  Zero(uri, 1, uri_t);

  uri->is_iri = is_iri;
  uri->scheme = str_new(aTHX_ URI_SIZE_scheme);
  uri->usr    = str_new(aTHX_ URI_SIZE_usr);
  uri->pwd    = str_new(aTHX_ URI_SIZE_pwd);
  uri->host   = str_new(aTHX_ URI_SIZE_host);
  uri->port   = str_new(aTHX_ URI_SIZE_port);
  uri->path   = str_new(aTHX_ URI_SIZE_path);
  uri->query  = str_new(aTHX_ URI_SIZE_query);
  uri->frag   = str_new(aTHX_ URI_SIZE_frag);

  // Build the blessed instance
  obj = newSViv((IV) uri);
  obj_ref = newRV_noinc(obj);
  sv_bless(obj_ref, gv_stashpv(class, GV_ADD));
  SvREADONLY_on(obj);

  // Scan the input string to fill the struct
  if (!SvTRUE(uri_str)) {
    src = "";
    len = 0;
  }
  else {
    // Copy input string *before* calling DO_UTF8() in case the SV is an object
    // with string overloading, which may trigger the utf8 flag.
    src = SvPV_nomg_const(uri_str, len);

    // Ensure the pv bytes are utf8-encoded
    if (!DO_UTF8(uri_str)) {
      uri_str = sv_2mortal(newSVpvn(src, len));
      sv_utf8_encode(uri_str);
      src = SvPV_const(uri_str, len);
    }
  }

  uri_scan(aTHX_ uri, src, len);

  return obj_ref;
}

static
void DESTROY(pTHX_ SV *uri_obj) {
  uri_t *uri = (uri_t*) SvIV(SvRV(uri_obj));
  str_free(aTHX_ uri->scheme);
  str_free(aTHX_ uri->usr);
  str_free(aTHX_ uri->pwd);
  str_free(aTHX_ uri->host);
  str_free(aTHX_ uri->port);
  str_free(aTHX_ uri->path);
  str_free(aTHX_ uri->query);
  str_free(aTHX_ uri->frag);
  Safefree(uri);
}

/*
 * Extras
 */
static
void uri_split(pTHX_ SV* uri) {
  const char* src;
  size_t idx = 0;
  size_t brk = 0;
  size_t len;

  if (!SvTRUE(uri)) {
    src = "";
    len = 0;
  }
  else {
    src = SvPV_nomg_const(uri, len);

    if (!DO_UTF8(uri)) {
      uri = sv_2mortal(newSVpvn(src, len));
      sv_utf8_encode(uri);
      src = SvPV_const(uri, len);
    }
  }

  dXSARGS;
  sp = mark;

  // Scheme
  brk = strcspn(&src[idx], ":/@?#");
  if (brk > 0 && strncmp(&src[idx + brk], "://", 3) == 0) {
    XPUSHs(sv_2mortal(newSVpvn(&src[idx], brk)));
    idx += brk + 3;

    // Authority
    brk = strcspn(&src[idx], "/?#");
    if (brk > 0) {
      XPUSHs(sv_2mortal(newSVpvn(&src[idx], brk)));
      idx += brk;
    } else {
      XPUSHs(sv_2mortal(newSVpvn("",0)));
    }
  }
  else {
    XPUSHs(&PL_sv_undef);
    XPUSHs(&PL_sv_undef);
  }

  // path
  brk = strcspn(&src[idx], "?#");
  if (brk > 0) {
    XPUSHs(sv_2mortal(newSVpvn(&src[idx], brk)));
    idx += brk;
  } else {
    XPUSHs(sv_2mortal(newSVpvn("", 0)));
  }

  // query
  if (src[idx] == '?') {
    ++idx; // skip past ?
    brk = strcspn(&src[idx], "#");
    if (brk > 0) {
      XPUSHs(sv_2mortal(newSVpvn(&src[idx], brk)));
      idx += brk;
    } else {
      XPUSHs(&PL_sv_undef);
    }
  } else {
    XPUSHs(&PL_sv_undef);
  }

  // fragment
  if (src[idx] == '#') {
    ++idx; // skip past #
    brk = len - idx;
    if (brk > 0) {
      XPUSHs(sv_2mortal(newSVpvn(&src[idx], brk)));
    } else {
      XPUSHs(&PL_sv_undef);
    }
  } else {
    XPUSHs(&PL_sv_undef);
  }

  PUTBACK;
}


MODULE = URI::Fast  PACKAGE = URI::Fast

PROTOTYPES: DISABLE

VERSIONCHECK: ENABLE

#-------------------------------------------------------------------------------
# URL-encoding
#-------------------------------------------------------------------------------
SV* encode(in, ...)
  SV *in
    PREINIT:
      SV *temp = NULL;
    CODE:
      if (items > 1) {
        temp = ST(1);
      }
      RETVAL = encode(aTHX_ in, temp);
    OUTPUT:
      RETVAL

SV* decode(in)
  SV* in
    CODE:
      RETVAL = decode(aTHX_ in);
    OUTPUT:
      RETVAL

#-------------------------------------------------------------------------------
# Constructors and destructors
#-------------------------------------------------------------------------------
SV* new(class, uri_str)
  const char* class
  SV* uri_str
  CODE:
    RETVAL = new(aTHX_ class, uri_str, 0);
  OUTPUT:
    RETVAL

SV* new_iri(class, uri_str)
  const char* class;
  SV* uri_str
  CODE:
    RETVAL = new(aTHX_ "URI::Fast::IRI", uri_str, 1);
  OUTPUT:
    RETVAL

void DESTROY(uri_obj)
  SV* uri_obj
  CODE:
    DESTROY(aTHX_ uri_obj);


#-------------------------------------------------------------------------------
# Clearers
#-------------------------------------------------------------------------------
void clear_scheme(uri_obj)
  SV* uri_obj
  CODE:
    clear_scheme(aTHX_ uri_obj);

void clear_path(uri_obj)
  SV* uri_obj
  CODE:
    clear_path(aTHX_ uri_obj);

void clear_query (uri_obj)
  SV* uri_obj
  CODE:
    clear_query(aTHX_ uri_obj);

void clear_frag(uri_obj)
  SV* uri_obj
  CODE:
    clear_frag(aTHX_ uri_obj);

void clear_usr(uri_obj)
  SV* uri_obj
  CODE:
    clear_usr(aTHX_ uri_obj);

void clear_pwd(uri_obj)
  SV* uri_obj
  CODE:
    clear_pwd(aTHX_ uri_obj);

void clear_host(uri_obj)
  SV* uri_obj
  CODE:
    clear_host(aTHX_ uri_obj);

void clear_port(uri_obj)
  SV* uri_obj
  CODE:
    clear_port(aTHX_ uri_obj);

void clear_auth(uri_obj)
  SV* uri_obj
  CODE:
    clear_auth(aTHX_ uri_obj);

#-------------------------------------------------------------------------------
# Raw getters
#-------------------------------------------------------------------------------
SV* raw_scheme(uri_obj)
  SV *uri_obj
  CODE:
    RETVAL = get_raw_scheme(aTHX_ uri_obj);
  OUTPUT:
    RETVAL

SV* raw_auth(uri_obj)
  SV *uri_obj
  CODE:
    RETVAL = get_raw_auth(aTHX_ uri_obj);
  OUTPUT:
    RETVAL

SV* raw_path(uri_obj)
  SV *uri_obj
  CODE:
    RETVAL = get_raw_path(aTHX_ uri_obj);
  OUTPUT:
    RETVAL

SV* raw_query(uri_obj)
  SV *uri_obj
  CODE:
    RETVAL = get_raw_query(aTHX_ uri_obj);
  OUTPUT:
    RETVAL

SV* raw_frag(uri_obj)
  SV *uri_obj
  CODE:
    RETVAL = get_raw_frag(aTHX_ uri_obj);
  OUTPUT:
    RETVAL

SV* raw_usr(uri_obj)
  SV *uri_obj
  CODE:
    RETVAL = get_raw_usr(aTHX_ uri_obj);
  OUTPUT:
    RETVAL

SV* raw_pwd(uri_obj)
  SV *uri_obj
  CODE:
    RETVAL = get_raw_pwd(aTHX_ uri_obj);
  OUTPUT:
    RETVAL

SV* raw_host(uri_obj)
  SV *uri_obj
  CODE:
    RETVAL = get_raw_host(aTHX_ uri_obj);
  OUTPUT:
    RETVAL

SV* raw_port(uri_obj)
  SV *uri_obj
  CODE:
    RETVAL = get_raw_port(aTHX_ uri_obj);
  OUTPUT:
    RETVAL

#-------------------------------------------------------------------------------
# Decoding getters
#-------------------------------------------------------------------------------
SV* get_scheme(uri_obj)
  SV *uri_obj
  CODE:
    RETVAL = get_scheme(aTHX_ uri_obj);
  OUTPUT:
    RETVAL

SV* get_path(uri_obj)
  SV *uri_obj
  CODE:
    RETVAL = get_path(aTHX_ uri_obj);
  OUTPUT:
    RETVAL

SV* get_query(uri_obj)
  SV *uri_obj
  CODE:
    RETVAL = get_query(aTHX_ uri_obj);
  OUTPUT:
    RETVAL

SV* get_frag(uri_obj)
  SV *uri_obj
  CODE:
    RETVAL = get_frag(aTHX_ uri_obj);
  OUTPUT:
    RETVAL

SV* get_usr(uri_obj)
  SV *uri_obj
  CODE:
    RETVAL = get_usr(aTHX_ uri_obj);
  OUTPUT:
    RETVAL

SV* get_pwd(uri_obj)
  SV *uri_obj
  CODE:
    RETVAL = get_pwd(aTHX_ uri_obj);
  OUTPUT:
    RETVAL

SV* get_host(uri_obj)
  SV *uri_obj
  CODE:
    RETVAL = get_host(aTHX_ uri_obj);
  OUTPUT:
    RETVAL

SV* get_port(uri_obj)
  SV *uri_obj
  CODE:
    RETVAL = get_port(aTHX_ uri_obj);
  OUTPUT:
    RETVAL

SV* get_auth(uri_obj)
  SV *uri_obj
  CODE:
    RETVAL = get_auth(aTHX_ uri_obj);
  OUTPUT:
    RETVAL


#-------------------------------------------------------------------------------
# Compound getters
#-------------------------------------------------------------------------------
SV* split_path(uri)
  SV* uri
  CODE:
    RETVAL = split_path(aTHX_ uri);
  OUTPUT:
    RETVAL

SV* get_query_keys(uri)
  SV* uri
  CODE:
    RETVAL = get_query_keys(aTHX_ uri);
  OUTPUT:
    RETVAL

SV* get_query_hash(uri)
  SV* uri
  CODE:
    RETVAL = query_hash(aTHX_ uri);
  OUTPUT:
    RETVAL

SV* get_param(uri, sv_key)
  SV* uri
  SV* sv_key
  CODE:
    RETVAL = get_param(aTHX_ uri, sv_key);
  OUTPUT:
    RETVAL


#-------------------------------------------------------------------------------
# Setters
#-------------------------------------------------------------------------------
void set_scheme(uri_obj, value)
  SV *uri_obj
  SV *value
  CODE:
    set_scheme(aTHX_ uri_obj, value);

void set_auth(uri_obj, value)
  SV *uri_obj
  SV *value
  CODE:
    set_auth(aTHX_ uri_obj, value);

void set_path(uri_obj, value)
  SV *uri_obj
  SV *value
  CODE:
    set_path(aTHX_ uri_obj, value);

void set_path_array(uri_obj, segments)
  SV *uri_obj
  SV *segments
  CODE:
    set_path_array(aTHX_ uri_obj, segments);

void set_query(uri_obj, value)
  SV *uri_obj
  SV *value
  CODE:
    set_query(aTHX_ uri_obj, value);

void set_frag(uri_obj, value)
  SV *uri_obj
  SV *value
  CODE:
    set_frag(aTHX_ uri_obj, value);

void set_usr(uri_obj, value)
  SV *uri_obj
  SV *value
  CODE:
    set_usr(aTHX_ uri_obj, value);

void set_pwd(uri_obj, value)
  SV *uri_obj
  SV *value
  CODE:
    set_pwd(aTHX_ uri_obj, value);

void set_host(uri_obj, value)
  SV *uri_obj
  SV *value
  CODE:
    set_host(aTHX_ uri_obj, value);

void set_port(uri_obj, value)
  SV *uri_obj
  SV *value
  CODE:
    set_port(aTHX_ uri_obj, value);

void set_param(uri, sv_key, sv_values, sv_separator)
  SV *uri
  SV *sv_key
  SV *sv_values
  SV *sv_separator
  CODE:
    set_param(aTHX_ uri, sv_key, sv_values, sv_separator);

void update_query_keyset(uri, sv_key_set, sv_separator)
  SV *uri
  SV *sv_key_set
  SV *sv_separator
  CODE:
    update_query_keyset(aTHX_ uri, sv_key_set, sv_separator);

#-------------------------------------------------------------------------------
# Extras
#-------------------------------------------------------------------------------
SV* to_string(uri_obj)
  SV* uri_obj
  CODE:
    RETVAL = to_string(aTHX_ uri_obj);
  OUTPUT:
    RETVAL

void explain(uri_obj)
  SV* uri_obj
  CODE:
    explain(aTHX_ uri_obj);

void debug(uri_obj)
  SV* uri_obj
  CODE:
    debug(aTHX_ uri_obj);

void uri_split(uri)
  SV* uri
  PREINIT:
    I32* temp;
  PPCODE:
    temp = PL_markstack_ptr++;
    uri_split(aTHX_ uri);

    if (PL_markstack_ptr != temp) {
      PL_markstack_ptr = temp;
      XSRETURN_EMPTY;
    }

    return;
