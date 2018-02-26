#include "perl.h"
#include <string.h>

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
    Inline_Stack_Push(newSVpv(&src[idx], brk));
    idx += brk + 3;

    // Authority
    brk = strcspn(&src[idx], "/?#");
    if (brk > 0) {
      Inline_Stack_Push(newSVpv(&src[idx], brk));
      idx += brk;
    } else {
      Inline_Stack_Push(newSVpv("",0));
    }
  }
  else {
    Inline_Stack_Push(&PL_sv_undef);
    Inline_Stack_Push(&PL_sv_undef);
  }

  // Path
  brk = strcspn(&src[idx], "?#");
  if (brk > 0) {
    Inline_Stack_Push(newSVpv(&src[idx], brk));
    idx += brk;
  } else {
    Inline_Stack_Push(newSVpv("",0));
  }

  // Query
  if (src[idx] == '?') {
    ++idx; // skip past ?
    brk = strcspn(&src[idx], "#");
    if (brk > 0) {
      Inline_Stack_Push(newSVpv(&src[idx], brk));
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
      Inline_Stack_Push(newSVpv(&src[idx], brk));
    } else {
      Inline_Stack_Push(&PL_sv_undef);
    }
  } else {
    Inline_Stack_Push(&PL_sv_undef);
  }

  Inline_Stack_Done;
}

void auth_join(SV* usr, SV* pwd, SV* host, SV* port) {
  STRLEN  len;
  char*   tmp;
  char    out[1024];
  int     idx = 0;

  Inline_Stack_Vars;
  Inline_Stack_Reset;

  if (SvTRUE(usr)) {
    tmp = SvPV(usr, len);
    strncpy(&out[idx], tmp, len);
    idx += len;

    if (SvTRUE(pwd)) {
      out[idx++] = ':';

      tmp = SvPV(pwd, len);
      strncpy(&out[idx], tmp, len);
      idx += len;
    }

    out[idx++] = '@';
  }

  if (SvTRUE(host)) {
    tmp = SvPV(host, len);
    strncpy(&out[idx], tmp, len);
    idx += len;

    if (SvTRUE(port)) {
      out[idx++] = ':';

      tmp = SvPV(port, len);
      strncpy(&out[idx], tmp, len);
      idx += len;
    }
  }

  if (idx > 0) {
    Inline_Stack_Push(newSVpv(out, idx));
  } else {
    Inline_Stack_Push(newSVpv("", 0));
  }

  Inline_Stack_Done;
}

void auth_split(SV* auth) {
  STRLEN  len;
  char*   src  = SvPV(auth, len);
  size_t  idx  = 0;
  size_t  brk1 = 0;
  size_t  brk2 = 0;

  SV* usr;
  SV* pwd;

  Inline_Stack_Vars;
  Inline_Stack_Reset;

  if (len == 0) {
    Inline_Stack_Push(&PL_sv_undef);
    Inline_Stack_Push(&PL_sv_undef);
    Inline_Stack_Push(&PL_sv_undef);
    Inline_Stack_Push(&PL_sv_undef);
  }
  else {
    // Credentials
    brk1 = strcspn(&src[idx], "@");

    if (brk1 > 0 && brk1 != len) {
      brk2 = strcspn(&src[idx], ":");

      if (brk2 > 0 && brk2 < brk1) {
        Inline_Stack_Push(newSVpv(&src[idx], brk2));
        idx += brk2 + 1;

        Inline_Stack_Push(newSVpv(&src[idx], brk1 - brk2 - 1));
        idx += brk1 - brk2;
      }
      else {
        Inline_Stack_Push(newSVpv(&src[idx], brk1));
        Inline_Stack_Push(&PL_sv_undef);
        idx += brk1 + 1;
      }
    }
    else {
      Inline_Stack_Push(&PL_sv_undef);
      Inline_Stack_Push(&PL_sv_undef);
    }

    // Location
    brk1 = strcspn(&src[idx], ":");

    if (brk1 > 0 && brk1 != (len - idx)) {
      Inline_Stack_Push(newSVpv(&src[idx], brk1));
      idx += brk1 + 1;
      Inline_Stack_Push(newSVpv(&src[idx], len - idx));
    }
    else {
      Inline_Stack_Push(newSVpv(&src[idx], len - idx));
      Inline_Stack_Push(&PL_sv_undef);
    }
  }

  Inline_Stack_Done;
}
