#include "../ppport.h"

#ifndef URI

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

// return uri_t* from blessed pointer ref
#define URI(obj) ((uri_t*) SvIV(SvRV(obj)))

// expands to member reference
#define URI_MEMBER(obj, member) (URI(obj)->member)

// quick sugar for calling uri_encode
#define URI_ENCODE_MEMBER(uri, mem, val, allow, alen) uri_encode(val, minnum(strlen(val), URI_SIZE(mem)), URI_MEMBER(uri, mem), allow, alen, URI_MEMBER(uri, is_iri))

// allowed characters; supplies (allowed, alen) to uri_encode/URI_ENCODE_MEMBER
#define URI_AUTH_CHARS "!$&'()*+,;=:@"
#define URI_AUTH_CHARS_LEN 14

#define URI_PATH_CHARS "!$&'()*+,;=:@/"
#define URI_PATH_CHARS_LEN 14

#define URI_QUERY_CHARS ":@?/&;="
#define URI_QUERY_CHARS_LEN 7

#define URI_QUERY_TOK_CHARS ":@?/"
#define URI_QUERY_TOK_CHARS_LEN 4

#define URI_FRAG_CHARS ":@?/"
#define URI_FRAG_CHARS_LEN 4

#define URI_USER_HOST_CHARS "!$&'()*+,;="
#define URI_USER_HOST_CHARS_LEN 11

// size constats
#define URI_SIZE_scheme 32
#define URI_SIZE_path   1024
#define URI_SIZE_query  2048
#define URI_SIZE_frag   64
#define URI_SIZE_usr    64
#define URI_SIZE_pwd    64
#define URI_SIZE_host   256
#define URI_SIZE_port   8

// enough to fit all pieces + 3 chars for separators (2 colons + @)
#define URI_SIZE_auth (3 + URI_SIZE_usr + URI_SIZE_pwd + URI_SIZE_host + URI_SIZE_port)
#define URI_SIZE(member) (URI_SIZE_##member)

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
  uri_scheme_t scheme;
  uri_query_t  query;
  uri_path_t   path;
  uri_host_t   host;
  uri_port_t   port;
  uri_frag_t   frag;
  uri_usr_t    usr;
  uri_pwd_t    pwd;
} uri_t;

#endif
