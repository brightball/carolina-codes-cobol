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
                PERFORM FILL-SPEAKER-HEADER
            END-IF
        WHEN HIT-TALKS > 0
            PERFORM FILL-TALK
        WHEN HIT-SPEAKERS > 0
            PERFORM FILL-SPEAKER
        WHEN HIT-YEAR-SPONSORS > 0
            IF FUNCTION TRIM(ARG2) = "missing-sponsor"
                PERFORM FILL-YEAR-SPONSOR-HEADER
            ELSE
                PERFORM FILL-YEAR-SPONSOR
            END-IF
        WHEN HIT-SPONSORS-SLUG > 0
            PERFORM FILL-SPONSOR-HEADER
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

FILL-TALK.
    STRING
        "slug" TAB "title" TAB "description" TAB "format" TAB
        "youtube_id" TAB "year" TAB "speaker_slug" TAB
        "languages" TAB "topics" NL
        "talk" TAB "Talk" TAB TAB TAB TAB "2026" TAB
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

FILL-YEAR.
    STRING
        "year" TAB "slug" TAB "name" TAB "status" NL
        "2026" TAB "2026" TAB "Carolina Code Conference 2026" TAB
        "past" NL
        DELIMITED BY SIZE INTO TSV.

END PROGRAM CATALOG-QUERY.
