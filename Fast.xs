#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

#include "src/defs.c"
#include "src/encoding.c"
#include "src/auth.c"
#include "src/query.c"

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

/*
 * Setters
 */
static
const char* set_scheme(pTHX_ SV* uri_obj, const char* value) {
  URI_ENCODE_MEMBER(uri_obj, scheme, value, "", 0);
  return URI_MEMBER(uri_obj, scheme);
}

static
const char* set_path(pTHX_ SV* uri_obj, const char* value) {
  URI_ENCODE_MEMBER(uri_obj, path, value, URI_PATH_CHARS, URI_PATH_CHARS_LEN);
  return URI_MEMBER(uri_obj, path);
}

static
const char* set_query(pTHX_ SV* uri_obj, const char* value) {
  URI_ENCODE_MEMBER(uri_obj, query, value, URI_QUERY_CHARS, URI_QUERY_CHARS_LEN);
  return value;
}

static
const char* set_frag(pTHX_ SV* uri_obj, const char* value) {
  URI_ENCODE_MEMBER(uri_obj, frag, value, URI_FRAG_CHARS, URI_FRAG_CHARS_LEN);
  return URI_MEMBER(uri_obj, frag);
}

static
const char* set_usr(pTHX_ SV* uri_obj, const char* value) {
  URI_ENCODE_MEMBER(uri_obj, usr, value, URI_USER_HOST_CHARS, URI_USER_HOST_CHARS_LEN);
  return URI_MEMBER(uri_obj, usr);
}

static
const char* set_pwd(pTHX_ SV* uri_obj, const char* value) {
  URI_ENCODE_MEMBER(uri_obj, pwd, value, URI_USER_HOST_CHARS, URI_USER_HOST_CHARS_LEN);
  return URI_MEMBER(uri_obj, pwd);
}

static
const char* set_host(pTHX_ SV* uri_obj, const char* value) {
  URI_ENCODE_MEMBER(uri_obj, host, value, URI_USER_HOST_CHARS, URI_USER_HOST_CHARS_LEN);
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
