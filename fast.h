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

// quick sugar for calling uri_encode
#define URI_ENCODE_MEMBER(uri, mem, val, allow) (\
  uri_encode(                           \
    (val),                              \
    minnum(strlen(val), URI_SIZE(mem)), \
    URI_MEMBER((uri), mem),             \
    (allow),                            \
    URI_MEMBER((uri), is_iri)           \
  )                                     \
)

// size constants
#define URI_SIZE_scheme   32
#define URI_SIZE_path   2048
#define URI_SIZE_query  2048
#define URI_SIZE_frag    128
#define URI_SIZE_usr     128
#define URI_SIZE_pwd     128
#define URI_SIZE_host    512
#define URI_SIZE_port      8

// enough to fit all pieces + 3 chars for separators (2 colons + @)
#define URI_SIZE_auth (3 + URI_SIZE_usr + URI_SIZE_pwd + URI_SIZE_host + URI_SIZE_port)

#define URI_SIZE(member) (URI_SIZE_##member)

/*
 * Uses memcpy to copy n bytes from src to dest and null-terminates. The caller
 * must ensure that dest is at least n + 1 bytes long and that src has at least
 * n bytes of data to copy.
 */
#define set_str(dest, src, n) \
  memcpy((dest), (src), (n)); \
  (dest)[n] = '\0';

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
