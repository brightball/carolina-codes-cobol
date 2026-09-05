>>SOURCE FORMAT FREE
*> Drive shipped HANDLE-GET (not a reimplementation).
IDENTIFICATION DIVISION.
PROGRAM-ID. CAROLINA-TEST.

ENVIRONMENT DIVISION.
CONFIGURATION SECTION.
REPOSITORY.
    FUNCTION ALL INTRINSIC.

DATA DIVISION.
WORKING-STORAGE SECTION.
01 PATH PIC X(512).
01 YEAR-Q PIC X(16).
01 STATUS-CODE PIC 9(3).
01 BODY PIC X(131072).
01 FAILED PIC 9(4) VALUE 0.
01 HIT USAGE BINARY-LONG VALUE 0.
01 FAKE-SQL-LOG PIC X(8192) EXTERNAL.

PROCEDURE DIVISION.
    MOVE SPACES TO FAKE-SQL-LOG
    PERFORM TEST-HEALTH
    PERFORM TEST-HEALTH-SLASH
    PERFORM TEST-IDENTITY
    PERFORM TEST-UNKNOWN-SLUG
    PERFORM TEST-SPEAKER-LIST
    PERFORM TEST-YEAR-SPEAKERS
    PERFORM TEST-YEAR-SPONSORS
    PERFORM TEST-YEARS
    IF FAILED > 0
        DISPLAY "handler tests failed (" FUNCTION TRIM(FAILED) ")"
        MOVE 1 TO RETURN-CODE
    ELSE
        DISPLAY "handler tests passed"
        MOVE 0 TO RETURN-CODE
    END-IF
    STOP RUN.

TEST-HEALTH.
    MOVE "/health" TO PATH
    MOVE SPACES TO YEAR-Q
    CALL "HANDLE-GET" USING PATH YEAR-Q STATUS-CODE BODY
    IF STATUS-CODE = 200
        DISPLAY "ok: /health returns 200"
    ELSE
        DISPLAY "FAIL: /health returns 200"
        ADD 1 TO FAILED
    END-IF
    MOVE 0 TO HIT
    INSPECT BODY TALLYING HIT FOR ALL '"status"'
    IF HIT > 0
        DISPLAY "ok: /health JSON has status"
    ELSE
        DISPLAY "FAIL: /health JSON has status"
        ADD 1 TO FAILED
    END-IF
    MOVE 0 TO HIT
    INSPECT BODY TALLYING HIT FOR ALL '"ok"'
    IF HIT > 0
        DISPLAY "ok: /health JSON has ok"
    ELSE
        DISPLAY "FAIL: /health JSON has ok"
        ADD 1 TO FAILED
    END-IF.

TEST-HEALTH-SLASH.
    MOVE "/health/" TO PATH
    MOVE SPACES TO YEAR-Q
    CALL "HANDLE-GET" USING PATH YEAR-Q STATUS-CODE BODY
    IF STATUS-CODE = 200
        DISPLAY "ok: /health/ returns 200"
    ELSE
        DISPLAY "FAIL: /health/ returns 200"
        ADD 1 TO FAILED
    END-IF
    MOVE 0 TO HIT
    INSPECT BODY TALLYING HIT FOR ALL "ok"
    IF HIT > 0
        DISPLAY "ok: /health/ body has ok"
    ELSE
        DISPLAY "FAIL: /health/ body has ok"
        ADD 1 TO FAILED
    END-IF.

TEST-IDENTITY.
    MOVE "/" TO PATH
    MOVE SPACES TO YEAR-Q
    CALL "HANDLE-GET" USING PATH YEAR-Q STATUS-CODE BODY
    IF STATUS-CODE = 200
        DISPLAY "ok: GET / returns 200"
    ELSE
        DISPLAY "FAIL: GET / returns 200"
        ADD 1 TO FAILED
    END-IF
    MOVE 0 TO HIT
    INSPECT BODY TALLYING HIT FOR ALL "COBOL"
    IF HIT > 0
        DISPLAY "ok: GET / language COBOL"
    ELSE
        DISPLAY "FAIL: GET / language COBOL"
        ADD 1 TO FAILED
    END-IF
    MOVE 0 TO HIT
    INSPECT BODY TALLYING HIT FOR ALL "POSIX sockets"
    IF HIT > 0
        DISPLAY "ok: GET / framework POSIX sockets"
    ELSE
        DISPLAY "FAIL: GET / framework POSIX sockets"
        ADD 1 TO FAILED
    END-IF
    MOVE 0 TO HIT
    INSPECT BODY TALLYING HIT FOR ALL "F#"
    IF HIT = 0
        DISPLAY "ok: not F#"
    ELSE
        DISPLAY "FAIL: not F#"
        ADD 1 TO FAILED
    END-IF.

TEST-UNKNOWN-SLUG.
    MOVE SPACES TO FAKE-SQL-LOG
    MOVE "/v1/speakers/no-such-slug" TO PATH
    MOVE SPACES TO YEAR-Q
    CALL "HANDLE-GET" USING PATH YEAR-Q STATUS-CODE BODY
    IF STATUS-CODE = 404
        DISPLAY "ok: unknown speaker slug returns 404"
    ELSE
        DISPLAY "FAIL: unknown speaker slug returns 404 got " STATUS-CODE
        ADD 1 TO FAILED
    END-IF
    MOVE 0 TO HIT
    INSPECT BODY TALLYING HIT FOR ALL "not_found"
    IF HIT > 0
        DISPLAY "ok: 404 body is not_found"
    ELSE
        DISPLAY "FAIL: 404 body is not_found"
        ADD 1 TO FAILED
    END-IF.

TEST-SPEAKER-LIST.
    MOVE SPACES TO FAKE-SQL-LOG
    MOVE "/v1/speakers" TO PATH
    MOVE SPACES TO YEAR-Q
    CALL "HANDLE-GET" USING PATH YEAR-Q STATUS-CODE BODY
    IF STATUS-CODE = 200
        DISPLAY "ok: unscoped speakers return 200"
    ELSE
        DISPLAY "FAIL: unscoped speakers return 200 got " STATUS-CODE
        ADD 1 TO FAILED
    END-IF
    MOVE 0 TO HIT
    INSPECT BODY TALLYING HIT FOR ALL '"slug":"diana-pham"'
    IF HIT >= 65
        DISPLAY "ok: unscoped speakers keep more than 64 rows ("
            FUNCTION TRIM(HIT) ")"
    ELSE
        DISPLAY "FAIL: unscoped speakers truncated at 64, got "
            FUNCTION TRIM(HIT)
        ADD 1 TO FAILED
    END-IF.

TEST-YEAR-SPEAKERS.
    MOVE SPACES TO FAKE-SQL-LOG
    MOVE "/v1/speakers" TO PATH
    MOVE "2026" TO YEAR-Q
    CALL "HANDLE-GET" USING PATH YEAR-Q STATUS-CODE BODY
    IF STATUS-CODE = 200
        DISPLAY "ok: year-scoped speakers return 200"
    ELSE
        DISPLAY "FAIL: year-scoped speakers return 200 got " STATUS-CODE
        ADD 1 TO FAILED
    END-IF
    MOVE 0 TO HIT
    INSPECT BODY TALLYING HIT FOR ALL '"data"'
    IF HIT > 0
        DISPLAY "ok: wrapped as data"
    ELSE
        DISPLAY "FAIL: wrapped as data"
        ADD 1 TO FAILED
    END-IF
    MOVE 0 TO HIT
    INSPECT BODY TALLYING HIT FOR ALL "languages"
    IF HIT > 0
        DISPLAY "ok: row has languages"
    ELSE
        DISPLAY "FAIL: row has languages body=" FUNCTION TRIM(BODY)
        ADD 1 TO FAILED
    END-IF
    MOVE 0 TO HIT
    INSPECT BODY TALLYING HIT FOR ALL "topics"
    IF HIT > 0
        DISPLAY "ok: row has topics"
    ELSE
        DISPLAY "FAIL: row has topics"
        ADD 1 TO FAILED
    END-IF
    MOVE 0 TO HIT
    INSPECT FAKE-SQL-LOG TALLYING HIT FOR ALL "v1_talks"
    IF HIT > 0
        DISPLAY "ok: queries v1_talks"
    ELSE
        DISPLAY "FAIL: queries v1_talks sql=" FUNCTION TRIM(FAKE-SQL-LOG)
        ADD 1 TO FAILED
    END-IF
    MOVE 0 TO HIT
    INSPECT FAKE-SQL-LOG TALLYING HIT FOR ALL "v1_year_speakers"
    IF HIT = 0
        DISPLAY "ok: does not query v1_year_speakers"
    ELSE
        DISPLAY "FAIL: does not query v1_year_speakers"
        ADD 1 TO FAILED
    END-IF.

TEST-YEAR-SPONSORS.
    MOVE "/v1/sponsors" TO PATH
    MOVE "2026" TO YEAR-Q
    CALL "HANDLE-GET" USING PATH YEAR-Q STATUS-CODE BODY
    IF STATUS-CODE = 200
        DISPLAY "ok: year-scoped sponsors return 200"
    ELSE
        DISPLAY "FAIL: year-scoped sponsors return 200"
        ADD 1 TO FAILED
    END-IF
    MOVE 0 TO HIT
    INSPECT BODY TALLYING HIT FOR ALL "tier"
    IF HIT > 0
        DISPLAY "ok: row includes tier"
    ELSE
        DISPLAY "FAIL: row includes tier body=" FUNCTION TRIM(BODY)
        ADD 1 TO FAILED
    END-IF
    MOVE 0 TO HIT
    INSPECT BODY TALLYING HIT FOR ALL "platinum"
    IF HIT > 0
        DISPLAY "ok: tier is platinum"
    ELSE
        DISPLAY "FAIL: tier is platinum"
        ADD 1 TO FAILED
    END-IF.

TEST-YEARS.
    MOVE "/v1/years" TO PATH
    MOVE SPACES TO YEAR-Q
    CALL "HANDLE-GET" USING PATH YEAR-Q STATUS-CODE BODY
    IF STATUS-CODE = 200
        DISPLAY "ok: /v1/years returns 200"
    ELSE
        DISPLAY "FAIL: /v1/years returns 200"
        ADD 1 TO FAILED
    END-IF
    MOVE 0 TO HIT
    INSPECT BODY TALLYING HIT FOR ALL '"data"'
    IF HIT > 0
        DISPLAY "ok: years wrapped as data"
    ELSE
        DISPLAY "FAIL: years wrapped as data"
        ADD 1 TO FAILED
    END-IF.

END PROGRAM CAROLINA-TEST.
