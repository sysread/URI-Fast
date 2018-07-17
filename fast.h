#ifndef URI

#define PERL_NO_GET_CONTEXT

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

// permitted characters
#define URI_CHARS_NONE          ""
#define URI_CHARS_AUTH          "!$&'()*+,;:=@"
#define URI_CHARS_PATH          "!$&'()*+,;:=@/"
#define URI_CHARS_PATH_SEGMENT  "!$&'()*+,;:=@"
#define URI_CHARS_HOST          "!$&'()[]*+,.;=@/"
#define URI_CHARS_QUERY         ":@?/&=;"
#define URI_CHARS_FRAG          ":@?/"
#define URI_CHARS_USER          "!$&'()*+,;="

// return uri_t* from blessed pointer ref
#define URI(obj) ((uri_t*) SvIV(SvRV( (obj) )))

// expands to member reference
#define URI_MEMBER(obj, member) (URI(obj)->member)

// size constants
#define URI_SIZE_scheme 32UL
#define URI_SIZE_usr    32UL
#define URI_SIZE_pwd    32UL
#define URI_SIZE_host   64UL
#define URI_SIZE_port    8UL
#define URI_SIZE_path   64UL
#define URI_SIZE_query  64UL
#define URI_SIZE_frag   32UL

// enough to fit all pieces + 3 chars for separators (2 colons + @)
#define URI_SIZE_auth (3 + URI_SIZE_usr + URI_SIZE_pwd + URI_SIZE_host + URI_SIZE_port)

// returns the size of the member in bytes
#define URI_SIZE(member) (URI_SIZE_##member)

// defines a clearer method
#define URI_SIMPLE_CLEARER(member) \
static void clear_##member(pTHX_ SV *uri) { \
  str_clear(aTHX_ URI_MEMBER(uri, member)); \
}

// Defines a setter method that accepts an unencoded value, encodes it,
// ignoring characters in string 'allowed', and copies the encoded value into
// slot 'member'.
#define URI_SIMPLE_SETTER(member, allowed) \
static void set_##member(pTHX_ SV *uri, SV *sv_value) { \
  SvGETMAGIC(sv_value); \
  if (SvOK(sv_value)) { \
    size_t len_value, len_enc; \
    const char *value = SvPV_const(sv_value, len_value); \
    char enc[len_value * 3]; \
    len_enc = uri_encode(value, len_value, enc, allowed, URI_MEMBER(uri, is_iri)); \
    str_set(aTHX_ URI_MEMBER(uri, member), enc, len_enc); \
  } \
  else { \
    str_clear(aTHX_ URI_MEMBER(uri, member)); \
  } \
}

// Defines a getter method that returns the raw, encoded value of the member slot.
#define URI_RAW_GETTER(member) \
static SV* get_raw_##member(pTHX_ SV *uri) { \
  uri_str_t *str = URI_MEMBER(uri, member); \
  return newSVpvn(str->length == 0 ? "" : str->string, str->length); \
}

// Defines a getter method that returns the decoded value of the member slot.
#define URI_SIMPLE_GETTER(member) \
static SV* get_##member(pTHX_ SV *uri) { \
  char decoded[ URI_MEMBER(uri, member)->length ]; \
  size_t len = uri_decode( \
    URI_MEMBER(uri, member)->string, \
    URI_MEMBER(uri, member)->length, \
    decoded, \
    "" \
  ); \
  SV *out = newSVpvn(decoded, len); \
  sv_utf8_decode(out); \
  return out; \
}

// Defines a getter method for a structured field that returns the value of the
// member slot with non-ASCII character decoded, while leaving reserved
// characters encoded.
#define URI_COMPOUND_GETTER(member) \
static SV* get_##member(pTHX_ SV *uri) { \
  char decoded[ URI_MEMBER(uri, member)->length ]; \
  size_t len = uri_decode_utf8( \
    URI_MEMBER(uri, member)->string, \
    URI_MEMBER(uri, member)->length, \
    decoded \
  ); \
  SV *out = newSVpvn(decoded, len); \
  sv_utf8_decode(out); \
  return out; \
}

/*
 * Allocate memory with Newx if it's
 * available - if it's an older perl
 * that doesn't have Newx then we
 * resort to using New.
 */
#ifndef Newx
#define Newx(v,n,t) New(0,v,n,t)
#endif

// av_top_index not available on Perls < 5.18
#ifndef av_top_index
#define av_top_index(av) av_len(av)
#endif

#endif
