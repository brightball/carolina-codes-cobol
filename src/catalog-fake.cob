>>SOURCE FORMAT FREE
*> Test catalog with the same PROGRAM-ID as the live wrapper so tests
*> link HANDLE-GET against this instead of libpq.
IDENTIFICATION DIVISION.
PROGRAM-ID. CATALOG-QUERY.

ENVIRONMENT DIVISION.
CONFIGURATION SECTION.
REPOSITORY.
    FUNCTION ALL INTRINSIC.

DATA DIVISION.
WORKING-STORAGE SECTION.
01 HIT-SPEAKER-SLUG USAGE BINARY-LONG VALUE 0.
01 HIT-SPEAKERS USAGE BINARY-LONG VALUE 0.
01 HIT-TALKS USAGE BINARY-LONG VALUE 0.
01 HIT-YEAR-SPONSORS USAGE BINARY-LONG VALUE 0.
01 HIT-SPONSORS-SLUG USAGE BINARY-LONG VALUE 0.
01 HIT-SPONSORS USAGE BINARY-LONG VALUE 0.
01 HIT-YEARS USAGE BINARY-LONG VALUE 0.
01 HIT-YEAR-SPEAKERS USAGE BINARY-LONG VALUE 0.
01 TAB PIC X VALUE X"09".
01 NL PIC X VALUE X"0A".
01 SLUG PIC X(128).
01 LOG-TMP PIC X(8192).
01 TSV-LEN USAGE BINARY-LONG VALUE 0.
01 LINE-BUF PIC X(256).
01 LINE-N USAGE BINARY-LONG.
01 MANY-I USAGE BINARY-LONG.
01 CH-I USAGE BINARY-LONG.

01 FAKE-SQL-LOG PIC X(8192) EXTERNAL.

LINKAGE SECTION.
01 SQL PIC X(1024).
01 ARG1 PIC X(256).
01 ARG2 PIC X(256).
01 NARGS USAGE BINARY-LONG.
01 TSV PIC X(262144).

PROCEDURE DIVISION USING SQL ARG1 ARG2 NARGS TSV.
    MOVE FUNCTION TRIM(SQL) TO SQL
    MOVE FAKE-SQL-LOG TO LOG-TMP
    STRING FUNCTION TRIM(LOG-TMP) DELIMITED BY SIZE
        FUNCTION TRIM(SQL) DELIMITED BY SIZE
        "|" DELIMITED BY SIZE
        INTO FAKE-SQL-LOG
    END-STRING
    MOVE 0 TO HIT-SPEAKER-SLUG HIT-SPEAKERS HIT-TALKS
        HIT-YEAR-SPONSORS HIT-SPONSORS-SLUG HIT-SPONSORS HIT-YEARS
        HIT-YEAR-SPEAKERS
    INSPECT SQL TALLYING HIT-YEAR-SPEAKERS FOR ALL "v1_year_speakers"
    INSPECT SQL TALLYING HIT-SPEAKER-SLUG FOR ALL "v1_speakers WHERE slug ="
    INSPECT SQL TALLYING HIT-SPEAKERS FOR ALL "v1_speakers"
    INSPECT SQL TALLYING HIT-TALKS FOR ALL "v1_talks"
    INSPECT SQL TALLYING HIT-YEAR-SPONSORS FOR ALL "v1_year_sponsors"
    INSPECT SQL TALLYING HIT-SPONSORS-SLUG FOR ALL "v1_sponsors WHERE slug"
    INSPECT SQL TALLYING HIT-SPONSORS FOR ALL "v1_sponsors"
    INSPECT SQL TALLYING HIT-YEARS FOR ALL "v1_years"
    MOVE SPACES TO TSV
    MOVE FUNCTION TRIM(ARG1) TO SLUG
    EVALUATE TRUE
        WHEN HIT-YEAR-SPEAKERS > 0
            MOVE "YEAR-SPEAKERS-USED" TO TSV
        WHEN HIT-SPEAKER-SLUG > 0
            IF SLUG = "diana-pham"
                PERFORM FILL-SPEAKER
            ELSE
                IF SLUG = "ada-lovelace"
                    PERFORM FILL-SPEAKER-WEBSITE
                ELSE
                    PERFORM FILL-SPEAKER-HEADER
                END-IF
            END-IF
        WHEN HIT-TALKS > 0
            PERFORM FILL-TALK
        WHEN HIT-SPEAKERS > 0
            PERFORM FILL-SPEAKER-MANY
        WHEN HIT-YEAR-SPONSORS > 0
            IF FUNCTION TRIM(ARG2) = "missing-sponsor"
                PERFORM FILL-YEAR-SPONSOR-HEADER
            ELSE
                PERFORM FILL-YEAR-SPONSOR
            END-IF
        WHEN HIT-SPONSORS-SLUG > 0
            IF SLUG = "flywheel"
                PERFORM FILL-SPONSOR
            ELSE
                PERFORM FILL-SPONSOR-HEADER
            END-IF
        WHEN HIT-SPONSORS > 0
            PERFORM FILL-YEAR-SPONSOR
        WHEN HIT-YEARS > 0
            PERFORM FILL-YEAR
        WHEN OTHER
            MOVE SPACES TO TSV
    END-EVALUATE
    GOBACK.

FILL-SPEAKER-HEADER.
    STRING
        "slug" TAB "first_name" TAB "last_name" TAB "name" TAB
        "tagline" TAB "bio" TAB "company" TAB "location" TAB
        "photo_path" TAB "twitter_url" TAB "linkedin_url" TAB
        "website_url" TAB "github_url" TAB "featured" NL
        DELIMITED BY SIZE INTO TSV.

FILL-SPEAKER.
    STRING
        "slug" TAB "first_name" TAB "last_name" TAB "name" TAB
        "tagline" TAB "bio" TAB "company" TAB "location" TAB
        "photo_path" TAB "twitter_url" TAB "linkedin_url" TAB
        "website_url" TAB "github_url" TAB "featured" NL
        "diana-pham" TAB "Diana" TAB "Pham" TAB "Diana Pham" TAB
        TAB TAB TAB TAB TAB TAB TAB TAB TAB "f" NL
        DELIMITED BY SIZE INTO TSV.

FILL-SPEAKER-WEBSITE.
    STRING
        "slug" TAB "first_name" TAB "last_name" TAB "name" TAB
        "tagline" TAB "bio" TAB "company" TAB "location" TAB
        "photo_path" TAB "twitter_url" TAB "linkedin_url" TAB
        "website_url" TAB "github_url" TAB "featured" NL
        "ada-lovelace" TAB "Ada" TAB "Lovelace" TAB "Ada Lovelace" TAB
        TAB TAB TAB TAB TAB TAB TAB
        "https://example.com/ada-lovelace" TAB TAB "f" NL
        DELIMITED BY SIZE INTO TSV.

FILL-SPEAKER-MANY.
    *> 80 rows: above the old OCCURS 64 cap so HANDLE-GET must keep them.
    MOVE SPACES TO TSV
    MOVE 0 TO TSV-LEN
    STRING
        "slug" TAB "first_name" TAB "last_name" TAB "name" TAB
        "tagline" TAB "bio" TAB "company" TAB "location" TAB
        "photo_path" TAB "twitter_url" TAB "linkedin_url" TAB
        "website_url" TAB "github_url" TAB "featured"
        DELIMITED BY SIZE INTO LINE-BUF
    PERFORM APPEND-TSV-LINE
    PERFORM VARYING MANY-I FROM 1 BY 1 UNTIL MANY-I > 80
        MOVE SPACES TO LINE-BUF
        STRING
            "diana-pham" TAB "Diana" TAB "Pham" TAB "Diana Pham" TAB
            TAB TAB TAB TAB TAB TAB TAB TAB TAB "f"
            DELIMITED BY SIZE INTO LINE-BUF
        PERFORM APPEND-TSV-LINE
    END-PERFORM.

APPEND-TSV-LINE.
    MOVE FUNCTION LENGTH(FUNCTION TRIM(LINE-BUF TRAILING)) TO LINE-N
    PERFORM VARYING CH-I FROM 1 BY 1 UNTIL CH-I > LINE-N
        ADD 1 TO TSV-LEN
        IF TSV-LEN <= 262144
            MOVE LINE-BUF(CH-I:1) TO TSV(TSV-LEN:1)
        END-IF
    END-PERFORM
    ADD 1 TO TSV-LEN
    IF TSV-LEN <= 262144
        MOVE NL TO TSV(TSV-LEN:1)
    END-IF.

FILL-TALK.
    STRING
        "slug" TAB "title" TAB "description" TAB "format" TAB
        "youtube_id" TAB "year" TAB "speaker_slug" TAB
        "languages" TAB "topics" NL
        "talk" TAB "Talk" TAB TAB TAB "dPhamYtFix01" TAB "2026" TAB
        "diana-pham" TAB "{php}" TAB "{development}" NL
        DELIMITED BY SIZE INTO TSV.

FILL-YEAR-SPONSOR-HEADER.
    STRING
        "slug" TAB "name" TAB "website" TAB "logo_path" TAB
        "description" TAB "blurb" TAB "tier" TAB "featured" TAB
        "year" TAB "twitter_url" TAB "linkedin_url" TAB
        "youtube_url" TAB "instagram_url" TAB "facebook_url" NL
        DELIMITED BY SIZE INTO TSV.

FILL-YEAR-SPONSOR.
    STRING
        "slug" TAB "name" TAB "website" TAB "logo_path" TAB
        "description" TAB "blurb" TAB "tier" TAB "featured" TAB
        "year" TAB "twitter_url" TAB "linkedin_url" TAB
        "youtube_url" TAB "instagram_url" TAB "facebook_url" NL
        "flywheel" TAB "Flywheel" TAB TAB TAB TAB TAB
        "platinum" TAB "f" TAB "2026" TAB TAB TAB TAB TAB NL
        DELIMITED BY SIZE INTO TSV.

FILL-SPONSOR-HEADER.
    STRING
        "slug" TAB "name" TAB "website" TAB "logo_path" TAB
        "description" TAB "twitter_url" TAB "linkedin_url" TAB
        "youtube_url" TAB "instagram_url" TAB "facebook_url" NL
        DELIMITED BY SIZE INTO TSV.

FILL-SPONSOR.
    STRING
        "slug" TAB "name" TAB "website" TAB "logo_path" TAB
        "description" TAB "twitter_url" TAB "linkedin_url" TAB
        "youtube_url" TAB "instagram_url" TAB "facebook_url" NL
        "flywheel" TAB "Flywheel" TAB "https://example.com/flywheel" TAB
        TAB TAB TAB TAB TAB TAB NL
        DELIMITED BY SIZE INTO TSV.

FILL-YEAR.
    STRING
        "year" TAB "slug" TAB "name" TAB "status" NL
        "2026" TAB "2026" TAB "Carolina Code Conference 2026" TAB
        "past" NL
        DELIMITED BY SIZE INTO TSV.

END PROGRAM CATALOG-QUERY.
