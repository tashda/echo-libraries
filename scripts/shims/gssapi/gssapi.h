/*
 * Routes <gssapi/gssapi.h> to Apple's GSS.framework, the supported Kerberos API on macOS.
 * The SDK's /usr/include/gssapi headers are Apple's MIT-compatibility layer, deprecated since
 * macOS 10.8; GSS.framework has the same functions and uses the same ticket cache.
 *
 * GSS.framework pulls in <MacTypes.h>, whose `typedef long Size` clashes with PostgreSQL's
 * `typedef size_t Size`. Apple's is renamed while its headers are read; no GSS API uses it.
 */
#ifndef ECHO_LIBRARIES_GSSAPI_SHIM_H
#define ECHO_LIBRARIES_GSSAPI_SHIM_H
#pragma push_macro("Size")
#define Size EchoLibrariesMacTypesSize
#include <GSS/gssapi.h>
#pragma pop_macro("Size")
#endif
