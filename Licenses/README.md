# Licences of the libraries Echo ships

| Library | Version | Licence | File |
|---|---|---|---|
| OpenSSL | 3.5.9 | Apache-2.0 | OpenSSL-3.5.9.txt |
| PostgreSQL (libpq, pg_dump, pg_restore, pg_dumpall, psql) | 18.6 | PostgreSQL | PostgreSQL-18.6.txt |
| MariaDB Connector/C | 3.4.11 | LGPL-2.1-or-later | MariaDB-Connector-C-3.4.11.txt |
| zstd | 1.5.7 | BSD-3-Clause | zstd-1.5.7.txt |
| lz4 (library) | 1.10.0 | BSD-2-Clause | lz4-1.10.0.txt |

MariaDB Connector/C is used unmodified, as its own dynamic library (EchoMariaDB.framework), which can
be replaced with another build of the same version. Its source is https://archive.mariadb.org/connector-c-3.4.11/mariadb-connector-c-3.4.11-src.tar.gz
(SHA-256 521c0712e9291fa96558df9e2ff431376a3a79329f13751896b694cae12765b4).
