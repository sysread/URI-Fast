#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include "../ppport.h"
#include "defs.c"

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

static
SV* set_auth(pTHX_ SV* uri_obj, const char* value) {
  char auth[URI_SIZE_auth];
  size_t len = uri_encode(value, strlen(value), (char*) &auth, URI_AUTH_CHARS, URI_AUTH_CHARS_LEN, URI_MEMBER(uri_obj, is_iri));
  uri_scan_auth(URI(uri_obj), auth, len);
  return newSVpv(auth, len);
}

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
