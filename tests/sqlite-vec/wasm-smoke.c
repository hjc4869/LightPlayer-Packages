#include <stdio.h>
#include <sqlite3.h>

#ifdef __EMSCRIPTEN_PTHREADS__
#include <pthread.h>
#endif

int sqlite3_vec_init(sqlite3 *database, char **error, const sqlite3_api_routines *api);

static int run_sql(void) {
    sqlite3 *database = NULL;
    char *error = NULL;
#ifdef __EMSCRIPTEN_PTHREADS__
    const int expected_threadsafe = 1;
#else
    const int expected_threadsafe = 0;
#endif
    if (sqlite3_libversion_number() != 3050004 || sqlite3_threadsafe() != expected_threadsafe) {
        fprintf(stderr, "Unexpected bundled SQLite version or threading mode\n");
        return 1;
    }
    if (sqlite3_auto_extension((void (*)(void))sqlite3_vec_init) != SQLITE_OK ||
        sqlite3_open(":memory:", &database) != SQLITE_OK) {
        fprintf(stderr, "Failed to register vec0 or open SQLite\n");
        return 1;
    }
    const char *sql =
        "CREATE TEMP TABLE checks (ok INTEGER NOT NULL CHECK (ok = 1));"
        "INSERT INTO checks SELECT sqlite_compileoption_used('OMIT_LOAD_EXTENSION');"
        "INSERT INTO checks SELECT sqlite_compileoption_used('ENABLE_COLUMN_METADATA');"
        "CREATE VIRTUAL TABLE documents USING fts5(content);"
        "INSERT INTO documents VALUES ('bundled SQLite search');"
        "INSERT INTO checks SELECT count(*) = 1 FROM documents WHERE documents MATCH 'SQLite';"
        "CREATE VIRTUAL TABLE bounds USING rtree(id, min_x, max_x);"
        "INSERT INTO bounds VALUES (1, 0, 10);"
        "INSERT INTO checks SELECT count(*) = 1 FROM bounds WHERE min_x <= 5 AND max_x >= 5;"
        "INSERT INTO checks SELECT vec_version() = 'v0.1.9';"
        "INSERT INTO checks SELECT vec_distance_L2('[1,2,3]', '[1,2,4]') = 1;"
        "INSERT INTO checks SELECT vec_distance_cosine('[1,0]', '[1,0]') = 0;"
        "INSERT INTO checks SELECT vec_distance_hamming(vec_bit(x'ffffffffffffffff'), vec_bit(x'0000000000000000')) = 64;"
        "INSERT INTO checks SELECT vec_distance_hamming(vec_bit(x'00000000ffffffff'), vec_bit(x'0000000000000000')) = 32;"
        "CREATE VIRTUAL TABLE vectors USING vec0(embedding float[3], label text);"
        "INSERT INTO vectors(rowid, embedding, label) VALUES"
        "(1, '[1,2,3]', 'first long metadata label'),"
        "(2, '[1,2,4]', 'second long metadata label'),"
        "(3, '[9,9,9]', 'third long metadata label');"
        "INSERT INTO checks SELECT (SELECT group_concat(rowid, ',') FROM ("
        "SELECT rowid FROM vectors WHERE embedding MATCH '[1,2,4]' AND k = 2 ORDER BY distance)) = '2,1';"
        "UPDATE vectors SET embedding = '[1,2,4]' WHERE rowid = 1;"
        "DELETE FROM vectors WHERE rowid = 2;"
        "INSERT INTO checks SELECT (SELECT count(*) FROM vectors) = 2;"
        "INSERT INTO checks SELECT group_concat(rowid) = '1' FROM ("
        "SELECT rowid FROM vectors WHERE embedding MATCH '[1,2,4]' AND k = 1 ORDER BY distance);";
    int result = sqlite3_exec(database, sql, NULL, NULL, &error);
    if (result != SQLITE_OK) {
        fprintf(stderr, "vec0 SQL failed: %s\n", error);
    }
    sqlite3_free(error);
    sqlite3_close(database);
    return result == SQLITE_OK ? 0 : 1;
}

#ifdef __EMSCRIPTEN_PTHREADS__
static void *run_worker(void *argument) {
    int *result = argument;
    *result = run_sql();
    return NULL;
}
#endif

int main(void) {
    int result = 1;
#ifdef __EMSCRIPTEN_PTHREADS__
    pthread_t worker;
    if (pthread_create(&worker, NULL, run_worker, &result) != 0 ||
        pthread_join(worker, NULL) != 0) {
        fprintf(stderr, "Failed to execute pthread worker\n");
        return 1;
    }
#else
    result = run_sql();
#endif
    if (result == 0) {
        puts("PASS: bundled WASM SQLite version, threading, FTS5, RTree, and vec0 SQL checks.");
    }
    return result;
}