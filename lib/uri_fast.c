#include "perl.h"
#include <stdlib.h>
#include <string.h>

/*
 * Allocate memory with Newx if it's
 * available - if it's an older perl
 * that doesn't have Newx then we
 * resort to using New.
 * */
#ifndef Newx
#define Newx(v,n,t) New(0,v,n,t)
#endif

// av_top_index not available on Perls < 5.18
#ifndef av_top_index
#define av_top_index(av) av_len(av)
#endif

#ifndef Uri
#define Uri(obj) ((uri_t*) SvIV(SvRV(obj)))
#endif

#ifndef Uri_Mem
#define Uri_Mem(obj, member) (Uri(obj)->member)
#endif

const char* pct_decode(const char*, size_t, size_t*);
size_t pct_decode_char(const char*, char*);

const char* pct_encode_reserved(const char*, size_t, size_t*, const char*);
const char* pct_encode_utf8(const char*, size_t, size_t*);
const char* pct_encode(const char*, size_t, size_t*, const char*);

SV* decode(SV*);
SV* encode(SV*, const char*);
SV* encode_reserved(SV*, const char*);
SV* encode_utf8(SV*);

typedef struct {
  char scheme[16];
  char auth[264];
  char path[256];
  char query[1024];
  char frag[32];

  char usr[64];
  char pwd[64];
  char host[128];
  char port[8];
} uri_t;

/*
 * Internal API
 */

/*
 * Clearers
 *   -note that these do not do other related cleanup (e.g. clearing auth triggering
 *    the clearing of usr/pwd/host/port)
 */
void clear_scheme(SV* uri_obj) { memset(&((Uri(uri_obj))->scheme), '\0', 16);   }
void clear_auth(SV* uri_obj)   { memset(&((Uri(uri_obj))->auth),   '\0', 264);  }
void clear_path(SV* uri_obj)   { memset(&((Uri(uri_obj))->path),   '\0', 256);  }
void clear_query(SV* uri_obj)  { memset(&((Uri(uri_obj))->query),  '\0', 1024); }
void clear_frag(SV* uri_obj)   { memset(&((Uri(uri_obj))->frag),   '\0', 32);   }
void clear_usr(SV* uri_obj)    { memset(&((Uri(uri_obj))->usr),    '\0', 64);   }
void clear_pwd(SV* uri_obj)    { memset(&((Uri(uri_obj))->pwd),    '\0', 64);   }
void clear_host(SV* uri_obj)   { memset(&((Uri(uri_obj))->host),   '\0', 128);  }
void clear_port(SV* uri_obj)   { memset(&((Uri(uri_obj))->port),   '\0', 8);    }

/*
 * Scans the authorization portion of the Uri string. This must only be called
 * *after* the 'auth' member has been populated (eg, by uri_scan).
 */
void uri_scan_auth (uri_t* uri) {
  size_t len  = strlen((char*) uri->auth);
  size_t idx  = 0;
  size_t brk1 = 0;
  size_t brk2 = 0;

  memset(&uri->usr,  '\0', 64);
  memset(&uri->pwd,  '\0', 64);
  memset(&uri->host, '\0', 128);
  memset(&uri->port, '\0', 8);

  if (len > 0) {
    // Credentials
    brk1 = strcspn(&uri->auth[idx], "@");

    if (brk1 > 0 && brk1 != len) {
      brk2 = strcspn(&uri->auth[idx], ":");

      if (brk2 > 0 && brk2 < brk1) {
        strncpy(uri->usr, &uri->auth[idx], brk2);
        idx += brk2 + 1;

        strncpy(uri->pwd, &uri->auth[idx], brk1 - brk2 - 1);
        idx += brk1 - brk2;
      }
      else {
        strncpy(uri->usr, &uri->auth[idx], brk1);
        idx += brk1 + 1;
      }
    }

    // Location
    brk1 = strcspn(&uri->auth[idx], ":");

    if (brk1 > 0 && brk1 != (len - idx)) {
      strncpy(uri->host, &uri->auth[idx], brk1);
      idx += brk1 + 1;
      strncpy(uri->port, &uri->auth[idx], len - idx);
    }
    else {
      strncpy(uri->host, &uri->auth[idx], len - idx);
    }
  }
}

/*
 * Scans a Uri string and populates the uri_t struct.
 */
void uri_scan(uri_t* uri, const char* src, STRLEN len) {
  size_t idx = 0;
  size_t brk = 0;

  // Scheme
  brk = strcspn(&src[idx], ":/@?#");
  if (brk > 0 && strncmp(&src[idx + brk], "://", 3) == 0) {
    strncpy(uri->scheme, &src[idx], brk);
    uri->scheme[brk] = '\0';
    idx += brk + 3;

    // Authority
    brk = strcspn(&src[idx], "/?#");
    if (brk > 0) {
      strncpy(uri->auth, &src[idx], brk);
      uri->auth[brk] = '\0';
      idx += brk;
      uri_scan_auth(uri);
    }
  }

  // Path
  brk = strcspn(&src[idx], "?#");
  if (brk > 0) {
    strncpy(uri->path, &src[idx], brk);
    uri->path[brk] = '\0';
    idx += brk;
  }

  // Query
  if (src[idx] == '?') {
    ++idx; // skip past ?
    brk = strcspn(&src[idx], "#");
    if (brk > 0) {
      strncpy(uri->query, &src[idx], brk);
      uri->query[brk] = '\0';
      idx += brk;
    }
  }

  // Fragment
  if (src[idx] == '#') {
    ++idx; // skip past #
    brk = len - idx;
    if (brk > 0) {
      strncpy(uri->frag, &src[idx], brk);
      uri->frag[brk] = '\0';
    }
  }
}

/*
 * Rebuilds the authority string: username:password@hostname:portnumber
 */
void uri_build_auth(uri_t* uri) {
  size_t len = 0;
  int idx = 0;

  memset(&uri->auth, '\0', 264);

  if (uri->usr[0] != '\0') {
    len = strlen((char*) &uri->usr);
    strncpy(&uri->auth[idx], (char*) &uri->usr, len);
    idx += len;

    if (uri->pwd[0] != '\0') {
      len = strlen((char*) &uri->pwd);
      uri->auth[idx++] = ':';
      strncpy(&uri->auth[idx], (char*) &uri->pwd, len);
      idx += len;
    }

    uri->auth[idx++] = '@';
  }

  if (uri->host[0] != '\0') {
    len = strlen((char*) &uri->host);
    strncpy(&uri->auth[idx], (char*) &uri->host, len);
    idx += len;

    if (uri->port[0] != '\0') {
      len = strlen((char*) &uri->port);
      uri->auth[idx++] = ':';
      strncpy(&uri->auth[idx], (char*) &uri->port, len);
      idx += len;
    }
  }

  uri->auth[idx++] = '\0';
}

/*
 * Perl API
 */

/*
 * Getters
 */
const char* get_scheme(SV* uri_obj) { return Uri_Mem(uri_obj, scheme); }
const char* get_auth(SV* uri_obj)   { return Uri_Mem(uri_obj, auth); }
const char* get_path(SV* uri_obj)   { return Uri_Mem(uri_obj, path); }
const char* get_query(SV* uri_obj)  { return Uri_Mem(uri_obj, query); }
const char* get_frag(SV* uri_obj)   { return Uri_Mem(uri_obj, frag); }
const char* get_usr(SV* uri_obj)    { return Uri_Mem(uri_obj, usr); }
const char* get_pwd(SV* uri_obj)    { return Uri_Mem(uri_obj, pwd); }
const char* get_host(SV* uri_obj)   { return Uri_Mem(uri_obj, host); }
const char* get_port(SV* uri_obj)   { return Uri_Mem(uri_obj, port); }

SV* query_hash(SV* uri) {
  const char* src = Uri_Mem(uri, query);
  const char* key;
  const char* val;
  size_t klen;
  size_t vlen;
  HV*  out = newHV();
  SV** ref;
  AV*  arr;
  SV*  tmp;

  while (src != NULL && src[0] != '\0') {
    key  = pct_decode(src, strcspn(src, "="), &klen);
    src  = strstr(src, "=");
    src += 1;
    val  = pct_decode(src, strcspn(src, "&"), &vlen);
    tmp  = newSVpv(val, vlen);

    SvUTF8_on(tmp);

    if (!hv_exists(out, key, klen)) {
      arr = newAV();
      hv_store(out, key, klen, newRV_noinc((SV*) arr), 0);
    }
    else {
      ref = hv_fetch(out, key, klen, 0);
      if (ref == NULL) croak("query_form: something went wrong");
      arr = (AV*) SvRV(*ref);
    }

    av_push(arr, tmp);

    src = strstr(src, "&");
    if (src == NULL) break;
    ++src;

    free((char*) key);
    free((char*) val);
  }

  return newRV_noinc((SV*) out);
}

SV* split_path(SV* uri) {
  size_t len, brk, idx = 0;
  const char* str;
  AV* arr = newAV();
  SV* tmp;

  str = pct_decode(Uri_Mem(uri, path), 0, &len);

  if (str[0] == '/') {
    ++str; // skip past leading /
  }

  while (idx < len) {
    brk = strcspn(&str[idx], "/");
    tmp = newSVpv(&str[idx], brk);
    SvUTF8_on(tmp);
    av_push(arr, tmp);
    idx += brk + 1;
  }

  return newRV_noinc((SV*) arr);
}

SV* get_query_keys(SV* uri) {
  const char* src;
  const char* tmp;
  size_t vlen;
  HV* out = newHV();

  for (src = Uri_Mem(uri, query); src != NULL && src[0] != '\0'; src = strstr(src, "&")) {
    if (src[0] == '&') {
      ++src;
    }

    tmp = pct_decode(src, strcspn(src, "="), &vlen);
    hv_store(out, tmp, vlen, &PL_sv_undef, 0);
    free(tmp);
  }

  return newRV_noinc((SV*) out);
}

SV* get_param(SV* uri, const char* key) {
  const char *tmp, *src = Uri_Mem(uri, query);
  char haystack[1024], needle[32];
  size_t klen, vlen;
  char* ptr;
  AV* out = newAV();
  SV* val;

  memset(haystack, '\0', 1024);
  sprintf(haystack, "&%s", Uri_Mem(uri, query));

  memset(needle, '\0', 32);
  klen = sprintf(needle, "&%s=", pct_encode(key, 0, 0, ""));

  for (ptr = strstr(haystack, needle); ptr != NULL; ptr = strstr(ptr, needle)) {
    ptr += klen;
    tmp = pct_decode(ptr, strcspn(ptr, "&"), &vlen);
    val = newSVpv(tmp, vlen);
    SvUTF8_on(val);
    av_push(out, val);
    free((char*) tmp);
  }

  return newRV_noinc((SV*) out);
}

/*
 * Setters
 */

const char* set_scheme(SV* uri_obj, const char* value, int no_triggers) {
  STRLEN len;
  const char* str = pct_encode(value, 0, &len, "");
  strncpy(Uri_Mem(uri_obj, scheme), str, len + 1);
  free((char*) str);
  return str;
}

const char* set_auth(SV* uri_obj, const char* value, int no_triggers) {
  STRLEN len;
  const char* str = pct_encode_utf8(value, 0, &len);
  strncpy(Uri_Mem(uri_obj, auth), str, len + 1);
  free((char*) str);
  if (!no_triggers) uri_scan_auth(Uri(uri_obj));
  return str;
}

const char* set_path(SV* uri_obj, const char* value, int no_triggers) {
  STRLEN len;
  const char* str = pct_encode(value, 0, &len, "/");
  strncpy(Uri_Mem(uri_obj, path), str, len + 1);
  free((char*) str);
  return str;
}

const char* set_query(SV* uri_obj, const char* value, int no_triggers) {
  strncpy(Uri_Mem(uri_obj, query), value, strlen(value) + 1);
  return value;
}

const char* set_frag(SV* uri_obj, const char* value, int no_triggers) {
  STRLEN len;
  const char* str = pct_encode(value, 0, &len, "");
  strncpy(Uri_Mem(uri_obj, frag), str, len + 1);
  free((char*) str);
  return str;
}

const char* set_usr(SV* uri_obj, const char* value, int no_triggers) {
  STRLEN len;
  const char* str = pct_encode(value, 0, &len, "");
  strncpy(Uri_Mem(uri_obj, usr), str, len + 1);
  free((char*) str);
  if (!no_triggers) uri_build_auth(Uri(uri_obj));
  return str;
}

const char* set_pwd(SV* uri_obj, const char* value, int no_triggers) {
  STRLEN len;
  const char* str = pct_encode(value, 0, &len, "");
  strncpy(Uri_Mem(uri_obj, pwd), str, len + 1);
  free((char*) str);
  if (!no_triggers) uri_build_auth(Uri(uri_obj));
  return str;
}

const char* set_host(SV* uri_obj, const char* value, int no_triggers) {
  STRLEN len;
  const char* str = pct_encode(value, 0, &len, "");
  strncpy(Uri_Mem(uri_obj, host), str, len + 1);
  free((char*) str);
  if (!no_triggers) uri_build_auth(Uri(uri_obj));
  return str;
}

const char* set_port(SV* uri_obj, const char* value, int no_triggers) {
  STRLEN len;
  const char* str = pct_encode(value, 0, &len, "");
  strncpy(Uri_Mem(uri_obj, port), str, len + 1);
  free((char*) str);
  if (!no_triggers) uri_build_auth(Uri(uri_obj));
  return str;
}

void set_param(SV* uri, const char* key, SV* sv_values) {
  SSize_t v;
  SV*     val;
  SV**    ref;
  char    dest[1024];
  const   char* enckey;
  const   char* encval;
  const   char* src;
  const   char* strval;
  size_t  i;
  size_t  j;
  size_t  klen;
  size_t  qlen = strlen(src);
  size_t  slen;
  size_t  vlen;
  AV*     av_values;

  src       = Uri_Mem(uri, query);
  enckey    = pct_encode(key, 0, &klen, "");
  qlen      = strlen(src);
  av_values = (AV*) SvRV(sv_values);
  v         = av_top_index(av_values);
  i         = 0;
  j         = 0;

  memset(dest, '\0', 1024);

  while (i < qlen) {
    while (strncmp(&src[i], enckey, klen) != 0) {
      dest[j++] = src[i++];

      if (i >= qlen) {
        break;
      }
    }

    i += strcspn(&src[i], "&");

    if (src[i] == '&') {
      ++i;
    }
  }

  if (dest[j - 1] == '&') {
    dest[j] = '\0';
    --j;
  }

  for (i = 0; i <= v; ++i) {
    ref = av_fetch(av_values, (SSize_t) i, 0);

    if (ref == NULL) {
      break;
    }

    val = *ref;

    if (!SvOK(val)) {
      break;
    }

    strval = SvPV(val, slen);
    encval = pct_encode(strval, slen, &vlen, "");

    if (j > 0 && dest[j] != '&') {
      dest[j++] = '&';
    }

    strncpy(&dest[j], enckey, klen);
    j += klen;

    dest[j++] = '=';

    strncpy(&dest[j], encval, vlen);
    j += vlen;

    free(encval);
  }

  free(enckey);
  clear_query(uri);
  strncpy(Uri_Mem(uri, query), dest, j);
}

/*
 * Other stuff
 */

SV* to_string(SV* uri_obj) {
  uri_t* uri = Uri(uri_obj);
  SV*    out = newSVpv("", 0);

  sv_catpv(out, uri->scheme);
  sv_catpv(out, "://");
  sv_catpv(out, uri->auth);
  sv_catpv(out, uri->path);

  if (uri->query[0] != '\0') {
    sv_catpv(out, "?");
    sv_catpv(out, uri->query);
  }

  if (uri->frag[0] != '\0') {
    sv_catpv(out, "#");
    sv_catpv(out, uri->frag);
  }

  return out;
}

void explain(SV* uri_obj) {
  printf("scheme: %s\n",  Uri_Mem(uri_obj, scheme));
  printf("auth: %s\n",    Uri_Mem(uri_obj, auth));
  printf("  -usr: %s\n",  Uri_Mem(uri_obj, usr));
  printf("  -pwd: %s\n",  Uri_Mem(uri_obj, pwd));
  printf("  -host: %s\n", Uri_Mem(uri_obj, host));
  printf("  -port: %s\n", Uri_Mem(uri_obj, port));
  printf("path: %s\n",    Uri_Mem(uri_obj, path));
  printf("query: %s\n",   Uri_Mem(uri_obj, query));
  printf("frag: %s\n",    Uri_Mem(uri_obj, frag));
}

SV* new(const char* class, SV* uri_str) {
  const char* src;
  STRLEN len;
  uri_t* uri;
  SV*    obj;
  SV*    obj_ref;

  Newx(uri, 1, uri_t);

  obj = newSViv((IV) uri);
  obj_ref = newRV_noinc(obj);
  sv_bless(obj_ref, gv_stashpv(class, GV_ADD));
  SvREADONLY_on(obj);

  clear_scheme(obj_ref);
  clear_auth(obj_ref);
  clear_path(obj_ref);
  clear_query(obj_ref);
  clear_frag(obj_ref);
  clear_usr(obj_ref);
  clear_pwd(obj_ref);
  clear_host(obj_ref);
  clear_port(obj_ref);

  src = SvPV_const(uri_str, len);
  uri_scan(uri, src, len);

  return obj_ref;
}

void DESTROY(SV* uri_obj) {
  uri_t* uri = (uri_t*) SvIV(SvRV(uri_obj));
  Safefree(uri);
}

/*
 * Extras
 */

inline
char is_allowed(char c, const char* allowed, size_t len) {
  size_t i;
  for (i = 0; i < len; ++i) {
    if (c == allowed[i]) {
      return 1;
    }
  }

  return 0;
}

const char* pct_encode_utf8(const char* src, size_t len, size_t* dest) {
  const unsigned char* in = (unsigned char*) src;
  char*  out;
  char   bytes = 0;
  size_t i = 0;
  size_t j = 0;

  if (len == 0) {
    len = strlen((char*) in);
  }

  out = malloc(((len * 3) + 1) * sizeof(char));
  memset(out, '\0', (sizeof(char) * len * 3) + 1);

  for (i = 0; i < len && in[i] != '\0'; ++i) {
    bytes = (in[i] >= 0   && in[i] <= 127) ? 1
          : (in[i] >= 192 && in[i] <= 223) ? 2
          : (in[i] >= 224 && in[i] <= 239) ? 3
          : (in[i] >= 240 && in[i] <= 247) ? 4
          : (in[i] >= 248 && in[i] <= 251) ? 5
          : (in[i] == 252 || in[i] == 253) ? 6
          : 0;

    if (bytes > 1) {
      j += sprintf(&out[j], "%%%02X", in[i]);

      while (bytes-- > 1) {
        j += sprintf(&out[j], "%%%02X", in[++i]);
      }
    }
    else {
      out[j++] = in[i];
    }
  }

  if (dest != NULL) {
    *dest = j;
  }

  return out;
}

const char* pct_encode_reserved(const char* in, size_t len, size_t* dest, const char* allowed) {
  char* out;
  size_t i = 0;
  size_t j = 0;
  size_t k = strlen((char*) allowed);
  size_t l = 0;

  if (len == 0) {
    len = strlen((char*) in);
  }

  out = malloc(((len * 3) + 1) * sizeof(char));
  memset(out, '\0', (sizeof(char) * len * 3) + 1);

  for (i = 0; i < len && in[i] != '\0'; ++i) {
    switch (in[i]) {
      case ':': case '@': case '&': case '=': case '?':  case '#':
      case '(': case ')': case '[': case ']': case '\'': case '/':
      case '+': case '!': case '*': case ';': case '$':  case ',':
      case '%': case ' ':
        if (k == 0 || is_allowed(in[i], allowed, k) == 0) {
          j += sprintf(&out[j], "%%%02X", in[i]);
          break;
        }
        // fall through otherwise
      default:
        out[j++] = in[i];
        break;
    }
  }

  if (dest != NULL) {
    *dest = j;
  }

  return out;
}

const char* pct_encode(const char* src, size_t len, size_t *dest, const char* allowed) {
  size_t rdest = 0;
  const char* res = pct_encode_reserved(src, len, &rdest, allowed);
  const char* out = pct_encode_utf8(res, rdest, dest);
  free((char*) res);
  return out;
}

SV* encode(SV* in, const char* allowed) {
  STRLEN len1, len2;
  const char *src, *dest;
  SV* out;

  src  = SvPV_const(in, len1);
  dest = pct_encode(src, len1, &len2, allowed);
  out  = newSVpv(dest, len2);
  sv_utf8_downgrade(out, FALSE);

  free((char*) dest);

  return out;
}

SV* encode_reserved(SV* in, const char* allowed) {
  STRLEN len1, len2;
  const char* src;
  const char* dest;
  SV* out;

  src  = SvPV_const(in, len1);
  dest = pct_encode_reserved(src, len1, &len2, allowed);
  out  = newSVpv(dest, len2);

  free((char*) dest);

  return out;
}

SV* encode_utf8(SV* in) {
  STRLEN len1, len2;
  const char* src;
  const char* dest;
  SV* out;

  src  = SvPV_const(in, len1);
  dest = pct_encode_utf8(src, len1, &len2);
  out  = newSVpv(dest, len2);
  sv_utf8_downgrade(out, FALSE);

  free((char*) dest);

  return out;
}

size_t pct_decode_char(const char* in, char* out) {
  size_t consumed = 1;
  unsigned int c;

  switch (in[0]) {
    case '+':
      out[0] = ' ';
      break;
    case '%':
      if (sscanf(in, "%%%2X", &c) == 1) {
        out[0] = (char) c;
        consumed = 3;
        break;
      }
    default:
      out[0] = in[0];
      break;
  }

  return consumed;
}

const char* pct_decode(const char* in, size_t len, size_t* dest) {
  char* out;
  unsigned int c;
  size_t i, j, brk;

  if (len == 0) {
    len = strlen((char*) in);
  }

  out = malloc((len + 1) * sizeof(char));
  memset(out, '\0', (sizeof(char) * len) + 1);

  i = 0;
  j = 0;

  while (i < len && in[i] != '\0') {
    // Find the next hex
    brk = strcspn(&in[i], "+%");

    if (brk + i > len) {
      brk = len - i;
    }

    // Unencoded text before the %; copy directly to out
    if (brk > 0) {
      strncpy(&out[j], &in[i], brk);
      i += brk; // move forward to the %
      j += brk;

      // Did that eat the entire input string?
      if (i >= len) {
        break;
      }
    }

    i += pct_decode_char(&in[i], &out[j++]);
  }

  if (dest != NULL) {
    *dest = j;
  }

  return out;
}

SV* decode(SV* in) {
  STRLEN len1, len2;
  const char* src;
  const char* dest;
  SV*   out;

  if (SvUTF8(in)) {
    in = sv_mortalcopy(in);

    SvUTF8_on(in);

    if (!sv_utf8_downgrade(in, TRUE)) {
      croak("decode: wide character in octet string");
    }

    src = SvPV_const(in, len1);
  }
  else {
    src = SvPV_const(in, len1);
  }

  dest = pct_decode(src, len1, &len2);
  out  = newSVpv(dest, len2);
  SvUTF8_on(out);

  free((char*) dest);

  return out;
}

void uri_split(SV* uri) {
  size_t idx = 0;
  size_t brk = 0;
  STRLEN len;
  const char* src = SvPV_const(uri, len);

  Inline_Stack_Vars;
  Inline_Stack_Reset;

  // Scheme
  brk = strcspn(&src[idx], ":/@?#");
  if (brk > 0 && strncmp(&src[idx + brk], "://", 3) == 0) {
    Inline_Stack_Push(sv_2mortal(newSVpv(&src[idx], brk)));
    idx += brk + 3;

    // Authority
    brk = strcspn(&src[idx], "/?#");
    if (brk > 0) {
      Inline_Stack_Push(sv_2mortal(newSVpv(&src[idx], brk)));
      idx += brk;
    } else {
      Inline_Stack_Push(sv_2mortal(newSVpv("",0)));
    }
  }
  else {
    Inline_Stack_Push(&PL_sv_undef);
    Inline_Stack_Push(&PL_sv_undef);
  }

  // Path
  brk = strcspn(&src[idx], "?#");
  if (brk > 0) {
    Inline_Stack_Push(sv_2mortal(newSVpv(&src[idx], brk)));
    idx += brk;
  } else {
    Inline_Stack_Push(sv_2mortal(newSVpv("",0)));
  }

  // Query
  if (src[idx] == '?') {
    ++idx; // skip past ?
    brk = strcspn(&src[idx], "#");
    if (brk > 0) {
      Inline_Stack_Push(sv_2mortal(newSVpv(&src[idx], brk)));
      idx += brk;
    } else {
      Inline_Stack_Push(&PL_sv_undef);
    }
  } else {
    Inline_Stack_Push(&PL_sv_undef);
  }

  // Fragment
  if (src[idx] == '#') {
    ++idx; // skip past #
    brk = len - idx;
    if (brk > 0) {
      Inline_Stack_Push(sv_2mortal(newSVpv(&src[idx], brk)));
    } else {
      Inline_Stack_Push(&PL_sv_undef);
    }
  } else {
    Inline_Stack_Push(&PL_sv_undef);
  }

  Inline_Stack_Done;
}

