import CLibpq
import CMariaDB
import Testing

/// The frameworks load from Swift and are built the way Echo needs: the right versions, OpenSSL,
/// Kerberos, and every MariaDB plugin built in. No server needed.
@Suite struct LibpqLoadTests {
    @Test func versionIsPostgreSQL18() {
        #expect(PQlibVersion() >= 180_000)
    }

    @Test func tlsIsOpenSSL() throws {
        let library = try #require(PQsslAttribute(nil, "library"))
        #expect(String(cString: library) == "OpenSSL")
    }

    @Test func kerberosIsBuiltIn() {
        // libpq only knows these connection keywords when it was built with GSSAPI.
        var keywords: Set<String> = []
        if let defaults = PQconndefaults() {
            var option = defaults
            while let keyword = option.pointee.keyword {
                keywords.insert(String(cString: keyword))
                option += 1
            }
            PQconninfoFree(defaults)
        }
        #expect(keywords.contains("krbsrvname"))
        #expect(keywords.contains("gssencmode"))
        #expect(keywords.contains("sslnegotiation"))
    }

    @Test func refusedConnectionFailsFast() {
        // Port 9 on localhost: nothing listens.
        let connection = PQconnectdb("host=127.0.0.1 port=9 connect_timeout=2 gssencmode=disable")
        defer { PQfinish(connection) }
        #expect(PQstatus(connection) == CONNECTION_BAD)
    }
}

@Suite struct MariaDBLoadTests {
    @Test func versionIsConnectorC34() {
        #expect(mysql_get_client_version() >= 30_400)
    }

    @Test func everySignInPluginIsBuiltIn() throws {
        let mysql = try #require(mysql_init(nil))
        defer { mysql_close(mysql) }
        for plugin in ["mysql_native_password", "caching_sha2_password", "sha256_password", "client_ed25519",
                       "parsec", "dialog", "mysql_clear_password", "auth_gssapi_client"] {
            #expect(mysql_client_find_plugin(mysql, plugin, MYSQL_CLIENT_AUTHENTICATION_PLUGIN) != nil, "\(plugin)")
        }
    }

    @Test func refusedConnectionFails() throws {
        let mysql = try #require(mysql_init(nil))
        defer { mysql_close(mysql) }
        #expect(mysql_real_connect(mysql, "127.0.0.1", "user", "password", nil, 9, nil, 0) == nil)
        #expect(mysql_errno(mysql) != 0)
    }
}
