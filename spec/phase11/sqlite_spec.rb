# frozen_string_literal: true

require 'open3'
require 'fileutils'

RSpec.describe 'Phase 11: sqlite 3.47.2 (Tier 3)', :thirdparty do
  it 'compiles the sqlite amalgamation and passes basic SQL tests', :slow do
    dir = File.join(ThirdpartyHelper::CACHE_DIR, 'sqlite')
    sqlite3_c = File.join(dir, 'sqlite3.c')

    skip 'sqlite amalgamation not in tmp/thirdparty_cache/sqlite/' unless File.exist?(sqlite3_c)

    Dir.mktmpdir('occ_sqlite_') do |tmp|
      test_src = File.join(tmp, 'sqlite_test.c')
      File.write(test_src, <<~'C')
        #include "sqlite3.h"
        #include <stdio.h>
        #include <stdlib.h>
        #include <string.h>

        static int count_rows(void *n, int argc, char **argv, char **col) {
          (*(int*)n)++;
          return 0;
        }

        int main(void) {
          sqlite3 *db;
          char *errmsg = 0;
          int rc, rows;

          rc = sqlite3_open(":memory:", &db);
          if (rc != SQLITE_OK) { printf("FAIL open rc=%d\n", rc); return 1; }

          rc = sqlite3_exec(db, "CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT, val REAL);", 0, 0, &errmsg);
          if (rc != SQLITE_OK) { printf("FAIL create rc=%d\n", rc); return 1; }

          rc = sqlite3_exec(db,
            "INSERT INTO t VALUES (1,'alice',1.5);"
            "INSERT INTO t VALUES (2,'bob',2.5);"
            "INSERT INTO t VALUES (3,'carol',3.5);",
            0, 0, &errmsg);
          if (rc != SQLITE_OK) { printf("FAIL insert rc=%d\n", rc); return 1; }

          rows = 0;
          rc = sqlite3_exec(db, "SELECT * FROM t;", count_rows, &rows, &errmsg);
          if (rc != SQLITE_OK || rows != 3) { printf("FAIL select all rc=%d rows=%d\n", rc, rows); return 1; }

          rows = 0;
          rc = sqlite3_exec(db, "SELECT * FROM t WHERE id > 1;", count_rows, &rows, &errmsg);
          if (rc != SQLITE_OK || rows != 2) { printf("FAIL select where rc=%d rows=%d\n", rc, rows); return 1; }

          rc = sqlite3_exec(db, "UPDATE t SET val=99.9 WHERE id=2;", 0, 0, &errmsg);
          if (rc != SQLITE_OK) { printf("FAIL update rc=%d\n", rc); return 1; }

          rc = sqlite3_exec(db, "DELETE FROM t WHERE id=3;", 0, 0, &errmsg);
          if (rc != SQLITE_OK) { printf("FAIL delete rc=%d\n", rc); return 1; }

          rc = sqlite3_exec(db, "BEGIN; INSERT INTO t VALUES (10,'x',0.0); COMMIT;", 0, 0, &errmsg);
          if (rc != SQLITE_OK) { printf("FAIL txn commit rc=%d\n", rc); return 1; }

          rc = sqlite3_exec(db, "BEGIN; INSERT INTO t VALUES (20,'y',0.0); ROLLBACK;", 0, 0, &errmsg);
          if (rc != SQLITE_OK) { printf("FAIL txn rollback rc=%d\n", rc); return 1; }
          rows = 0;
          rc = sqlite3_exec(db, "SELECT * FROM t;", count_rows, &rows, &errmsg);
          if (rc != SQLITE_OK || rows != 3) { printf("FAIL after rollback rc=%d rows=%d\n", rc, rows); return 1; }

          sqlite3_stmt *stmt;
          rc = sqlite3_prepare_v2(db, "SELECT id, name FROM t ORDER BY id;", -1, &stmt, 0);
          if (rc != SQLITE_OK) { printf("FAIL prepare rc=%d\n", rc); return 1; }
          int count = 0;
          while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) count++;
          sqlite3_finalize(stmt);
          if (rc != SQLITE_DONE || count != 3) { printf("FAIL step rc=%d count=%d\n", rc, count); return 1; }

          sqlite3_close(db);
          printf("sqlite ok\n");
          return 0;
        }
      C

      output = File.join(tmp, 'sqlite_test')
      result = occ_compile(test_src, sqlite3_c, output: output,
                                                flags: ["-I#{dir}",
                                                        '-DSQLITE_THREADSAFE=0',
                                                        '-DSQLITE_OMIT_LOAD_EXTENSION'])
      expect_compiled(result)

      run = shell(output)
      expect(run[:stdout].strip).to eq('sqlite ok')
      expect_ran_ok(run)
    end
  end
end
