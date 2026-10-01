/* MariaDB Connector/C (echo-libraries), for MySQL and MariaDB. Only mysql-wire imports this module. */
#include "mysql.h"
#include "errmsg.h"
#include "mysqld_error.h"
#include "mariadb_version.h"

/* mysql/client_plugin.h can't be part of the module: the installed copy includes ma_compress.h,
   which Connector/C 3.4.11 doesn't install. mysql.h already declares mysql_client_find_plugin;
   this is the one plugin type Echo asks for. */
#ifndef MYSQL_CLIENT_AUTHENTICATION_PLUGIN
#define MYSQL_CLIENT_AUTHENTICATION_PLUGIN 2
#endif
