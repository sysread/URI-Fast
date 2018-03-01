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

unsigned char* pct_encode_reserved(unsigned char*, size_t, size_t*, const char*);
unsigned char* pct_encode_utf8(unsigned char*, size_t, size_t*);
unsigned char* pct_encode(unsigned char*, size_t, size_t*, const char*);
SV* encode(SV*, const char*);
SV* encode_reserved(SV*, const char*);
SV* encode_utf8(SV*);

typedef struct {
  char scheme[16];
  char auth[264];
  char path[256];
  char query[512];
  char frag[32];

  char usr[64];
  char pwd[64];
  char host[128];
  char port[8];
} uri_t;

SV* decode(SV* in) {
  SV* out;
  dSP;

  ENTER;
  SAVETMPS;

  PUSHMARK(SP);
  EXTEND(SP, 1);
  PUSHs(sv_mortalcopy(in));
  PUTBACK;

  call_pv("URI::Encode::XS::uri_decode_utf8", G_SCALAR);
  SPAGAIN;

  out = newSVsv(POPs);

  PUTBACK;
  FREETMPS;
  LEAVE;

  return out;
}

/*
 * Internal API
 */

/*
 * Scans the authorization portion of the URI string. This must only be called
 * *after* the 'auth' member has been populated (eg, by uri_scan).
 */
void uri_scan_auth (uri_t* uri) {
  size_t len  = strlen(uri->auth);
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
 * Scans a URI string and populates the uri_t struct.
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
    len = strlen(&uri->usr);
    strncpy(&uri->auth[idx], &uri->usr, len);
    idx += len;

    if (uri->pwd[0] != '\0') {
      len = strlen(&uri->pwd);
      uri->auth[idx++] = ':';
      strncpy(&uri->auth[idx], &uri->pwd, len);
      idx += len;
    }

    uri->auth[idx++] = '@';
  }

  if (uri->host[0] != '\0') {
    len = strlen(&uri->host);
    strncpy(&uri->auth[idx], &uri->host, len);
    idx += len;

    if (uri->port[0] != '\0') {
      len = strlen(&uri->port);
      uri->auth[idx++] = ':';
      strncpy(&uri->auth[idx], &uri->port, len);
      idx += len;
    }
  }

  uri->auth[idx++] = '\0';
}

/*
 * Perl API
 */

inline
uri_t* to_uri(SV* uri_obj) {
  return ((uri_t*) SvIV(SvRV(uri_obj)));
}

/*
 * Clearers
 */
void clear_scheme(SV* uri_obj) { memset(&((to_uri(uri_obj))->scheme), '\0', 16);  }
void clear_auth(SV* uri_obj)   { memset(&((to_uri(uri_obj))->auth),   '\0', 264); }
void clear_path(SV* uri_obj)   { memset(&((to_uri(uri_obj))->path),   '\0', 256); }
void clear_query(SV* uri_obj)  { memset(&((to_uri(uri_obj))->query),  '\0', 512); }
void clear_frag(SV* uri_obj)   { memset(&((to_uri(uri_obj))->frag),   '\0', 32);  }
void clear_usr(SV* uri_obj)    { memset(&((to_uri(uri_obj))->usr),    '\0', 64);  }
void clear_pwd(SV* uri_obj)    { memset(&((to_uri(uri_obj))->pwd),    '\0', 64);  }
void clear_host(SV* uri_obj)   { memset(&((to_uri(uri_obj))->host),   '\0', 128); }
void clear_port(SV* uri_obj)   { memset(&((to_uri(uri_obj))->port),   '\0', 8);   }

/*
 * Getters
 */
const char* get_scheme(SV* uri_obj) { return to_uri(uri_obj)->scheme; }
const char* get_auth(SV* uri_obj)   { return to_uri(uri_obj)->auth;   }
const char* get_path(SV* uri_obj)   { return to_uri(uri_obj)->path;   }
const char* get_query(SV* uri_obj)  { return to_uri(uri_obj)->query;  }
const char* get_frag(SV* uri_obj)   { return to_uri(uri_obj)->frag;   }
const char* get_usr(SV* uri_obj)    { return to_uri(uri_obj)->usr;    }
const char* get_pwd(SV* uri_obj)    { return to_uri(uri_obj)->pwd;    }
const char* get_host(SV* uri_obj)   { return to_uri(uri_obj)->host;   }
const char* get_port(SV* uri_obj)   { return to_uri(uri_obj)->port;   }

/*
 * Setters
 */
SV* set_scheme(SV* uri_obj, SV* value, int no_triggers) {
  STRLEN len;
  char* str = SvPV(value, len);
  uri_t* uri = to_uri(uri_obj);
  strncpy(uri->scheme, str, len + 1);
  return newSVsv(value);
}

SV* set_auth(SV* uri_obj, SV* value, int no_triggers) {
  STRLEN len;
  value = sv_2mortal(encode_utf8(value));
  char* str = SvPV(value, len);
  uri_t* uri = to_uri(uri_obj);
  strncpy(uri->auth, str, len + 1);
  if (!no_triggers) uri_scan_auth(uri);
  return newSVsv(value);
}

SV* set_path(SV* uri_obj, SV* value, int no_triggers) {
  STRLEN len;
  value = sv_2mortal(encode(value, "/"));
  char* str = SvPV(value, len);
  uri_t* uri = to_uri(uri_obj);
  strncpy(uri->path, str, len + 1);
  return newSVsv(value);
}

SV* set_query(SV* uri_obj, SV* value, int no_triggers) {
  STRLEN len;
  char* str = SvPV(value, len);
  uri_t* uri = to_uri(uri_obj);
  strncpy(uri->query, str, len + 1);
  return newSVsv(value);
}

SV* set_frag(SV* uri_obj, SV* value, int no_triggers) {
  STRLEN len;
  value = sv_2mortal(encode(value, ""));
  char* str = SvPV(value, len);
  uri_t* uri = to_uri(uri_obj);
  strncpy(uri->frag, str, len + 1);
  return newSVsv(value);
}

SV* set_usr(SV* uri_obj, SV* value, int no_triggers) {
  STRLEN len;
  value = sv_2mortal(encode(value, ""));
  char* str = SvPV(value, len);
  uri_t* uri = to_uri(uri_obj);
  strncpy(uri->usr, str, len + 1);
  if (!no_triggers) uri_build_auth(uri);
  return newSVsv(value);
}

SV* set_pwd(SV* uri_obj, SV* value, int no_triggers) {
  STRLEN len;
  value = sv_2mortal(encode(value, ""));
  char* str = SvPV(value, len);
  uri_t* uri = to_uri(uri_obj);
  strncpy(uri->pwd, str, len + 1);
  if (!no_triggers) uri_build_auth(uri);
  return newSVsv(value);
}

SV* set_host(SV* uri_obj, SV* value, int no_triggers) {
  STRLEN len;
  value = sv_2mortal(encode(value, ""));
  char* str = SvPV(value, len);
  uri_t* uri = to_uri(uri_obj);
  strncpy(uri->host, str, len + 1);
  if (!no_triggers) uri_build_auth(uri);
  return newSVsv(value);
}

SV* set_port(SV* uri_obj, SV* value, int no_triggers) {
  STRLEN len;
  value = sv_2mortal(encode(value, ""));
  char* str = SvPV(value, len);
  uri_t* uri = to_uri(uri_obj);
  strncpy(uri->port, str, len + 1);
  if (!no_triggers) uri_build_auth(uri);
  return newSVsv(value);
}

void split_path(SV* uri_obj) {
  uri_t* uri = to_uri(uri_obj);
  size_t len = strlen(uri->path);
  size_t idx = 0;
  size_t brk = 0;

  Inline_Stack_Vars;
  Inline_Stack_Reset;

  if (uri->path[0] == '/') {
    ++idx; // skip past leading /
  }

  while (idx < len) {
    brk = strcspn(&uri->path[idx], "/");
    SV* tmp = newSVpv(&uri->path[idx], brk);
    Inline_Stack_Push(sv_2mortal(tmp));
    idx += brk + 1;
  }

  Inline_Stack_Done;
}

void get_query_keys(SV* uri_obj) {
  uri_t* uri = to_uri(uri_obj);
  size_t len = strlen(uri->query);
  char*  src = uri->query;
  SV*    tmp;

  Inline_Stack_Vars;
  Inline_Stack_Reset;

  while (src != NULL && src[0] != '\0') {
    if (src[0] == '&') {
      ++src; // skip past &
    }

    tmp = newSVpv(src, strcspn(src, "="));
    Inline_Stack_Push(sv_2mortal(tmp));
    src = strstr(src, "&");
  }

  Inline_Stack_Done;
}

void get_param(SV* uri_obj, const char* key) {
  uri_t* uri = to_uri(uri_obj);
  size_t len = strlen(uri->query);
  char*  src = uri->query;
  size_t brk = 0;
  SV*    tmp;

  Inline_Stack_Vars;
  Inline_Stack_Reset;

  while (src[0] != '\0') {
    if (src[0] == '&') {
      ++src; // skip past &
    }

    src = strstr(src, key);

    if (src == NULL) {
      break;
    }

    brk = strcspn(src, "=");
    src += brk;

    if (src[0] == '\0') {
      break;
    }

    if (src[0] != '=') {
      continue;
    }

    ++src; // skip past '='
    brk = strcspn(src, "&");
    tmp = newSVpv(src, brk);
    Inline_Stack_Push(sv_2mortal(tmp));
    src += brk;
  }

  Inline_Stack_Done;
}

SV* to_string(SV* uri_obj) {
  uri_t* uri = to_uri(uri_obj);
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
  printf("scheme: %s\n",  get_scheme(uri_obj));
  printf("auth: %s\n",    get_auth(uri_obj));
  printf("  -usr: %s\n",  get_usr(uri_obj));
  printf("  -pwd: %s\n",  get_pwd(uri_obj));
  printf("  -host: %s\n", get_host(uri_obj));
  printf("  -port: %s\n", get_port(uri_obj));
  printf("path: %s\n",    get_path(uri_obj));
  printf("query: %s\n",   get_query(uri_obj));
  printf("frag: %s\n",    get_frag(uri_obj));
}

SV* new(const char* class, SV* uri_str) {
  STRLEN len;
  char*  src;
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

  src = SvPV(uri_str, len);
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
char is_allowed(unsigned char c, const char* allowed, size_t len) {
  size_t i;
  for (i = 0; i < len; ++i) {
    if (c == allowed[i]) {
      return 1;
    }
  }

  return 0;
}

unsigned char* pct_encode_utf8(unsigned char* in, size_t len, size_t* dest) {
  unsigned char* out;
  size_t i = 0;
  size_t j = 0;
  char bytes = 0;

  Newx(out, len * 3, unsigned char);
  memset(out, '0', sizeof(unsigned char) * len * 3);

  for (i = 0; i < len; ++i) {
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

  *dest = j;

  return out;
}

unsigned char* pct_encode_reserved(unsigned char* in, size_t len, size_t* dest, const char* allowed) {
  unsigned char* out;
  size_t i = 0;
  size_t j = 0;
  size_t k = strlen(allowed);
  size_t l = 0;

  Newx(out, len * 3, unsigned char);
  memset(out, '0', sizeof(unsigned char) * len * 3);

  for (i = 0; i < len; ++i) {
    switch (in[i]) {
      case ':': case '@': case '&': case '=': case '?':  case '#':
      case '(': case ')': case '[': case ']': case '\'': case '/':
      case '+': case '!': case '*': case ';': case '$':  case ',':
      case '%':
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

  *dest = j;

  return out;
}

unsigned char* pct_encode(unsigned char* src, size_t len, size_t *dest, const char* allowed) {
  size_t rdest = 0;
  char* res = pct_encode_reserved(src, len, &rdest, allowed);
  char* out = pct_encode_utf8(res, rdest, dest);
  Safefree(res);
  return out;
}

SV* encode(SV* in, const char* allowed) {
  STRLEN len1, len2;
  char* src;
  char* dest;
  SV*   out;

  src  = SvPV(in, len1);
  dest = pct_encode(src, len1, &len2, allowed);
  out  = newSVpv(dest, len2);

  Safefree(dest);

  return out;
}

SV* encode_reserved(SV* in, const char* allowed) {
  STRLEN len1, len2;
  char* src;
  char* dest;
  SV*   out;

  src  = SvPV(in, len1);
  dest = pct_encode_reserved(src, len1, &len2, allowed);
  out  = newSVpv(dest, len2);

  Safefree(dest);

  return out;
}

SV* encode_utf8(SV* in) {
  STRLEN len1, len2;
  char*  src;
  char*  dest;
  SV*    out;

  src  = SvPV(in, len1);
  dest = pct_encode_utf8(src, len1, &len2);
  out  = newSVpv(dest, len2);

  Safefree(dest);

  return out;
}

void uri_split(SV* uri) {
  STRLEN  len;
  char*   src = SvPV(uri, len);
  size_t  idx = 0;
  size_t  brk = 0;

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

