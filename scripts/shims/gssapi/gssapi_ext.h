/*
 * Stand-in for MIT Kerberos' <gssapi/gssapi_ext.h>, which Apple's GSS (Heimdal) does not ship.
 *
 * PostgreSQL includes it for gss_store_cred_into(), which only the server uses (storing delegated
 * credentials, src/backend/libpq/be-gssapi-common.c). The client side (libpq, pg_dump, psql) needs
 * only the standard GSS-API, all of it in Apple's GSS.framework. Used for client-only builds.
 */
#ifndef ECHO_LIBRARIES_GSSAPI_EXT_SHIM_H
#define ECHO_LIBRARIES_GSSAPI_EXT_SHIM_H
#include <gssapi/gssapi.h> /* the shim next to this file */
#endif
