#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#include "src/defs.c"
#include "src/encoding.c"
#include "src/query.c"

/*
 * Utils
 */

// min of two numbers
size_t minnum(size_t x, size_t y) {
  return x <= y ? x : y;
}

// max of two numbers
size_t maxnum(size_t x, size_t y) {
  return x >= y ? x : y;
}

/*
 * Internal API
 */

/*
 * Clearers
 */
static void clear_scheme(pTHX_ SV* uri_obj) { memset(&((URI(uri_obj))->scheme), '\0', sizeof(uri_scheme_t)); }
static void clear_path(pTHX_ SV* uri_obj)   { memset(&((URI(uri_obj))->path),   '\0', sizeof(uri_path_t));   }
static void clear_query(pTHX_ SV* uri_obj)  { memset(&((URI(uri_obj))->query),  '\0', sizeof(uri_query_t));  }
static void clear_frag(pTHX_ SV* uri_obj)   { memset(&((URI(uri_obj))->frag),   '\0', sizeof(uri_frag_t));   }
static void clear_usr(pTHX_ SV* uri_obj)    { memset(&((URI(uri_obj))->usr),    '\0', sizeof(uri_usr_t));    }
static void clear_pwd(pTHX_ SV* uri_obj)    { memset(&((URI(uri_obj))->pwd),    '\0', sizeof(uri_pwd_t));    }
static void clear_host(pTHX_ SV* uri_obj)   { memset(&((URI(uri_obj))->host),   '\0', sizeof(uri_host_t));   }
static void clear_port(pTHX_ SV* uri_obj)   { memset(&((URI(uri_obj))->port),   '\0', sizeof(uri_port_t));   }

static
void clear_auth(pTHX_ SV* uri_obj) {
  clear_usr(aTHX_ uri_obj);
  clear_pwd(aTHX_ uri_obj);
  clear_host(aTHX_ uri_obj);
  clear_port(aTHX_ uri_obj);
}

/*
 * Scans the authorization portion of the URI string
 */
static
void uri_scan_auth(uri_t* uri, const char* auth, const size_t len) {
  size_t idx  = 0;
  size_t brk1 = 0;
  size_t brk2 = 0;
  size_t i;

  memset(&uri->usr,  '\0', sizeof(uri_usr_t));
  memset(&uri->pwd,  '\0', sizeof(uri_pwd_t));
  memset(&uri->host, '\0', sizeof(uri_host_t));
  memset(&uri->port, '\0', sizeof(uri_port_t));

  if (len > 0) {
    // Credentials
    brk1 = minnum(len, strcspn(&auth[idx], "@"));

    if (brk1 > 0 && brk1 != len) {
      brk2 = minnum(len - idx, strcspn(&auth[idx], ":"));

      if (brk2 > 0 && brk2 < brk1) {
        strncpy(uri->usr, &auth[idx], minnum(brk2, URI_SIZE_usr));
        idx += brk2 + 1;

        strncpy(uri->pwd, &auth[idx], minnum(brk1 - brk2 - 1, URI_SIZE_pwd));
        idx += brk1 - brk2;
      }
      else {
        strncpy(uri->usr, &auth[idx], minnum(brk1, URI_SIZE_usr));
        idx += brk1 + 1;
      }
    }

    // Location
    brk1 = minnum(len - idx, strcspn(&auth[idx], ":"));

    if (brk1 > 0 && brk1 != (len - idx)) {
      strncpy(uri->host, &auth[idx], minnum(brk1, URI_SIZE_host));
      idx += brk1 + 1;

      for (i = 0; i < (len - idx) && i < URI_SIZE_port; ++i) {
        if (!isdigit(auth[i + idx])) {
          memset(&uri->port, '\0', URI_SIZE_port + 1);
          break;
        }
        else {
          uri->port[i] = auth[i + idx];
        }
      }
    }
    else {
      strncpy(uri->host, &auth[idx], minnum(len - idx, URI_SIZE_host));
    }
  }
}

/*
 * Scans a URI string and populates the uri_t struct.
 */
static
void uri_scan(uri_t* uri, const char* src, size_t len) {
  size_t idx = 0;
  size_t brk = 0;

  // Scheme
  brk = minnum(len, strcspn(&src[idx], ":/@?#"));
  if (brk > 0 && strncmp(&src[idx + brk], "://", 3) == 0) {
    strncpy(uri->scheme, &src[idx], minnum(brk, URI_SIZE_scheme));
    uri->scheme[brk] = '\0';
    idx += brk + 3;

    // Authority
    brk = minnum(len - idx, strcspn(&src[idx], "/?#"));
    if (brk > 0) {
      uri_scan_auth(uri, &src[idx], brk);
      idx += brk;
    }
  }

  // path
  brk = minnum(len - idx, strcspn(&src[idx], "?#"));
  if (brk > 0) {
    strncpy(uri->path, &src[idx], minnum(brk, URI_SIZE_path));
    uri->path[brk] = '\0';
    idx += brk;
  }

  // query
  if (src[idx] == '?') {
    ++idx; // skip past ?
    brk = minnum(len - idx, strcspn(&src[idx], "#"));
    if (brk > 0) {
      strncpy(uri->query, &src[idx], minnum(brk, URI_SIZE_query));
      uri->query[brk] = '\0';
      idx += brk;
    }
  }

  // fragment
  if (src[idx] == '#') {
    ++idx; // skip past #
    brk = len - idx;
    if (brk > 0) {
      strncpy(uri->frag, &src[idx], minnum(brk, URI_SIZE_frag));
      uri->frag[brk] = '\0';
    }
  }
}

/*
 * Perl API
 */

/*
 * Getters
 */
static const char* get_scheme(pTHX_ SV* uri_obj) { return URI_MEMBER(uri_obj, scheme); }
static const char* get_path(pTHX_ SV* uri_obj)   { return URI_MEMBER(uri_obj, path);   }
static const char* get_query(pTHX_ SV* uri_obj)  { return URI_MEMBER(uri_obj, query);  }
static const char* get_frag(pTHX_ SV* uri_obj)   { return URI_MEMBER(uri_obj, frag);   }
static const char* get_usr(pTHX_ SV* uri_obj)    { return URI_MEMBER(uri_obj, usr);    }
static const char* get_pwd(pTHX_ SV* uri_obj)    { return URI_MEMBER(uri_obj, pwd);    }
static const char* get_host(pTHX_ SV* uri_obj)   { return URI_MEMBER(uri_obj, host);   }
static const char* get_port(pTHX_ SV* uri_obj)   { return URI_MEMBER(uri_obj, port);   }

static
SV* get_auth(pTHX_ SV* uri_obj) {
  uri_t* uri = URI(uri_obj);
  SV* out = newSVpv("", 0);

  if (uri->usr[0] != '\0') {
    if (uri->pwd[0] != '\0') {
      sv_catpvf(out, "%s:%s@", uri->usr, uri->pwd);
    } else {
      sv_catpvf(out, "%s@", uri->usr);
    }
  }

  if (uri->host[0] != '\0') {
    if (uri->port[0] != '\0') {
      sv_catpvf(out, "%s:%s", uri->host, uri->port);
    } else {
      sv_catpv(out, uri->host);
    }
  }

  return out;
}

static
SV* split_path(pTHX_ SV* uri) {
  size_t brk, idx = 0;
  AV* arr = newAV();
  SV* tmp;

  size_t path_len = strlen(URI_MEMBER(uri, path));
  char str[path_len + 1];
  size_t len = uri_decode(URI_MEMBER(uri, path), path_len, str);

  if (str[0] == '/') {
    ++idx; // skip past leading /
  }

  while (idx < len) {
    brk = strcspn(&str[idx], "/");
    tmp = newSVpvn(&str[idx], brk);
    sv_utf8_decode(tmp);
    av_push(arr, tmp);
    idx += brk + 1;
  }

  return newRV_noinc((SV*) arr);
}

static
SV* get_param(pTHX_ SV* uri, SV* sv_key) {
  int is_iri = URI_MEMBER(uri, is_iri);
  char* query = URI_MEMBER(uri, query);
  size_t qlen = strlen(query), klen, vlen, elen;
  uri_query_scanner_t scanner;
  uri_query_token_t token;
  AV* out = newAV();
  SV* value;

  SvGETMAGIC(sv_key);
  const char* key = SvPV_nomg_const(sv_key, klen);
  char enc_key[(klen * 3) + 2];
  elen = uri_encode(key, klen, enc_key, ":@?/", 4, is_iri);

  query_scanner_init(&scanner, query, qlen);

  while (!query_scanner_done(&scanner)) {
    query_scanner_next(&scanner, &token);
    if (token.type == DONE) continue;

    if (strncmp(enc_key, token.key, maxnum(elen, token.key_length)) == 0) {
      if (token.type == PARAM) {
        char val[token.value_length + 1];
        vlen = uri_decode(token.value, token.value_length, val);
        value = newSVpv(val, vlen);
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
static
const char* set_scheme(pTHX_ SV* uri_obj, const char* value) {
  URI_ENCODE_MEMBER(uri_obj, scheme, value, "", 0);
  return URI_MEMBER(uri_obj, scheme);
}

static
SV* set_auth(pTHX_ SV* uri_obj, const char* value) {
  char auth[URI_SIZE_auth];
  size_t len = uri_encode(value, strlen(value), (char*) &auth, "!$&'()*+,;=:@", 14, URI_MEMBER(uri_obj, is_iri));
  uri_scan_auth(URI(uri_obj), auth, len);
  return newSVpv(auth, len);
}

static
const char* set_path(pTHX_ SV* uri_obj, const char* value) {
  URI_ENCODE_MEMBER(uri_obj, path, value, "!$&'()*+,;=:@/", 14);
  return URI_MEMBER(uri_obj, path);
}

static
const char* set_query(pTHX_ SV* uri_obj, const char* value) {
  URI_ENCODE_MEMBER(uri_obj, query, value, ":@?/&=", 6);
  return value;
}

static
const char* set_frag(pTHX_ SV* uri_obj, const char* value) {
  URI_ENCODE_MEMBER(uri_obj, frag, value, ":@?/", 4);
  return URI_MEMBER(uri_obj, frag);
}

static
const char* set_usr(pTHX_ SV* uri_obj, const char* value) {
  URI_ENCODE_MEMBER(uri_obj, usr, value, "!$&'()*+,;=", 11);
  return URI_MEMBER(uri_obj, usr);
}

static
const char* set_pwd(pTHX_ SV* uri_obj, const char* value) {
  URI_ENCODE_MEMBER(uri_obj, pwd, value, "!$&'()*+,;=", 11);
  return URI_MEMBER(uri_obj, pwd);
}

static
const char* set_host(pTHX_ SV* uri_obj, const char* value) {
  URI_ENCODE_MEMBER(uri_obj, host, value, "!$&'()*+,;=", 1);
  return URI_MEMBER(uri_obj, host);
}

static
const char* set_port(pTHX_ SV* uri_obj, const char* value) {
  size_t len = minnum(strlen(value), URI_SIZE_port);
  size_t i;

  for (i = 0; i < len; ++i) {
    if (isdigit(value[i])) {
      URI_MEMBER(uri_obj, port)[i] = value[i];
    }
    else {
      clear_port(aTHX_ uri_obj);
      break;
    }
  }

  return URI_MEMBER(uri_obj, port);
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
    klen = uri_encode(key, klen, enc_key, ":@?/", 4, is_iri);

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

  clear_query(aTHX_ uri);
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
  klen = uri_encode(key, strlen(key), enc_key, ":@?/", 4, is_iri);

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

    vlen = uri_encode(strval, slen, &dest[off], ":@?/", 4, is_iri);
    off += vlen;
  }

  clear_query(aTHX_ uri);
  strncpy(URI_MEMBER(uri, query), dest, off);
}

/*
 * Other stuff
 */

static
SV* to_string(pTHX_ SV* uri_obj) {
  uri_t* uri = URI(uri_obj);
  SV*    out = newSVpv("", 0);

  if (uri->scheme[0] != '\0') {
    sv_catpv(out, uri->scheme);
    sv_catpv(out, "://");
  }

  sv_catsv(out, sv_2mortal(get_auth(aTHX_ uri_obj)));
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

static
void explain(pTHX_ SV* uri_obj) {
  printf("scheme: %s\n",  URI_MEMBER(uri_obj, scheme));
  printf("auth:\n");
  printf("  -usr: %s\n",  URI_MEMBER(uri_obj, usr));
  printf("  -pwd: %s\n",  URI_MEMBER(uri_obj, pwd));
  printf("  -host: %s\n", URI_MEMBER(uri_obj, host));
  printf("  -port: %s\n", URI_MEMBER(uri_obj, port));
  printf("path: %s\n",    URI_MEMBER(uri_obj, path));
  printf("query: %s\n",   URI_MEMBER(uri_obj, query));
  printf("frag: %s\n",    URI_MEMBER(uri_obj, frag));
}

static
SV* new(pTHX_ const char* class, SV* uri_str) {
  const char* src;
  size_t len;
  uri_t* uri;
  SV*    obj;
  SV*    obj_ref;

  Newx(uri, 1, uri_t);
  memset(uri, '\0', sizeof(uri_t));

  obj = newSViv((IV) uri);
  obj_ref = newRV_noinc(obj);
  sv_bless(obj_ref, gv_stashpv(class, GV_ADD));
  SvREADONLY_on(obj);

  SvGETMAGIC(uri_str);

  if (!SvOK(uri_str)) {
    src = "";
    len = 0;
  }
  else {
    src = SvPV_nomg_const(uri_str, len);
  }

  uri_scan(uri, src, len);

  return obj_ref;
}

static
SV* new_iri(pTHX_ const char* class, SV* uri_str) {
  SV* obj = new(aTHX_ "URI::Fast::IRI", uri_str);
  URI_MEMBER(obj, is_iri) = 1;
  return obj;
}

static
void DESTROY(pTHX_ SV* uri_obj) {
  uri_t* uri = (uri_t*) SvIV(SvRV(uri_obj));
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

  SvGETMAGIC(uri);

  if (!SvOK(uri)) {
    src = "";
    len = 0;
  }
  else {
    src = SvPV_nomg_const(uri, len);
  }

  dXSARGS;
  sp = mark;

  // Scheme
  brk = strcspn(&src[idx], ":/@?#");
  if (brk > 0 && strncmp(&src[idx + brk], "://", 3) == 0) {
    XPUSHs(sv_2mortal(newSVpv(&src[idx], brk)));
    idx += brk + 3;

    // Authority
    brk = strcspn(&src[idx], "/?#");
    if (brk > 0) {
      XPUSHs(sv_2mortal(newSVpv(&src[idx], brk)));
      idx += brk;
    } else {
      XPUSHs(sv_2mortal(newSVpv("",0)));
    }
  }
  else {
    XPUSHs(&PL_sv_undef);
    XPUSHs(&PL_sv_undef);
  }

  // path
  brk = strcspn(&src[idx], "?#");
  if (brk > 0) {
    XPUSHs(sv_2mortal(newSVpv(&src[idx], brk)));
    idx += brk;
  } else {
    XPUSHs(sv_2mortal(newSVpv("",0)));
  }

  // query
  if (src[idx] == '?') {
    ++idx; // skip past ?
    brk = strcspn(&src[idx], "#");
    if (brk > 0) {
      XPUSHs(sv_2mortal(newSVpv(&src[idx], brk)));
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
      XPUSHs(sv_2mortal(newSVpv(&src[idx], brk)));
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

#-------------------------------------------------------------------------------
# URL-encoding
#-------------------------------------------------------------------------------
SV* encode(in, ...)
  SV* in
    PREINIT:
      I32* temp;
    CODE:
      temp = PL_markstack_ptr++;
      RETVAL = encode(aTHX_ in);
      PL_markstack_ptr = temp;
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
    RETVAL = new(aTHX_ class, uri_str);
  OUTPUT:
    RETVAL

SV* new_iri(class, uri_str)
  const char* class;
  SV* uri_str
  CODE:
    RETVAL = new_iri(aTHX_ class, uri_str);
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
# Simple getters
#-------------------------------------------------------------------------------
const char* get_scheme(uri_obj)
  SV* uri_obj
  CODE:
    RETVAL = get_scheme(aTHX_ uri_obj);
  OUTPUT:
    RETVAL

const char* get_path(uri_obj)
  SV* uri_obj
  CODE:
    RETVAL = get_path(aTHX_ uri_obj);
  OUTPUT:
    RETVAL

const char* get_query(uri_obj)
  SV* uri_obj
  CODE:
    RETVAL = get_query(aTHX_ uri_obj);
  OUTPUT:
    RETVAL

const char* get_frag(uri_obj)
  SV* uri_obj
  CODE:
    RETVAL = get_frag(aTHX_ uri_obj);
  OUTPUT:
    RETVAL

const char* get_usr(uri_obj)
  SV* uri_obj
  CODE:
    RETVAL = get_usr(aTHX_ uri_obj);
  OUTPUT:
    RETVAL

const char* get_pwd(uri_obj)
  SV* uri_obj
  CODE:
    RETVAL = get_pwd(aTHX_ uri_obj);
  OUTPUT:
    RETVAL

const char* get_host(uri_obj)
  SV* uri_obj
  CODE:
    RETVAL = get_host(aTHX_ uri_obj);
  OUTPUT:
    RETVAL

const char* get_port(uri_obj)
  SV* uri_obj
  CODE:
    RETVAL = get_port(aTHX_ uri_obj);
  OUTPUT:
    RETVAL

SV* get_auth(uri_obj)
  SV* uri_obj
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
const char* set_scheme(uri_obj, value)
  SV* uri_obj
  const char* value
  CODE:
    RETVAL = set_scheme(aTHX_ uri_obj, value);
  OUTPUT:
    RETVAL

SV* set_auth(uri_obj, value)
  SV* uri_obj
  const char* value
  CODE:
    RETVAL = set_auth(aTHX_ uri_obj, value);
  OUTPUT:
    RETVAL

const char* set_path(uri_obj, value)
  SV* uri_obj
  const char* value
  CODE:
    RETVAL = set_path(aTHX_ uri_obj, value);
  OUTPUT:
    RETVAL

const char* set_query(uri_obj, value)
  SV* uri_obj
  const char* value
  CODE:
    RETVAL = set_query(aTHX_ uri_obj, value);
  OUTPUT:
    RETVAL

const char* set_frag(uri_obj, value)
  SV* uri_obj
  const char* value
  CODE:
    RETVAL = set_frag(aTHX_ uri_obj, value);
  OUTPUT:
    RETVAL

const char* set_usr(uri_obj, value)
  SV* uri_obj
  const char* value
  CODE:
    RETVAL = set_usr(aTHX_ uri_obj, value);
  OUTPUT:
    RETVAL

const char* set_pwd(uri_obj, value)
  SV* uri_obj
  const char* value
  CODE:
    RETVAL = set_pwd(aTHX_ uri_obj, value);
  OUTPUT:
    RETVAL

const char* set_host(uri_obj, value)
  SV* uri_obj
  const char* value
  CODE:
    RETVAL = set_host(aTHX_ uri_obj, value);
  OUTPUT:
    RETVAL

const char* set_port(uri_obj, value)
  SV* uri_obj
  const char* value
  CODE:
    RETVAL = set_port(aTHX_ uri_obj, value);
  OUTPUT:
    RETVAL

void set_param(uri, sv_key, sv_values, separator)
  SV* uri
  SV* sv_key
  SV* sv_values
  char separator
  CODE:
    set_param(aTHX_ uri, sv_key, sv_values, separator);

void update_query_keyset(uri, sv_key_set, separator)
  SV* uri
  SV* sv_key_set
  char separator
  CODE:
    update_query_keyset(aTHX_ uri, sv_key_set, separator);

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
