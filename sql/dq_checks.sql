------------------------------------------------------------------------------------------
-- DATA QUALITY CHECKS - 5G PROFILE (SANDBOX2.AUTO_5G_PROFILE)
--   run after 02 for the same month:
--       vsql -v RUN_MNTH=202512 -f dq_checks.sql
--   one row per check (ACTUAL vs EXPECTED -> PASS / FAIL) + a summary row
--   any FAIL = hold the business / network extracts until it is explained
--
--   A. source -> target reconciliation   subscribers, active base, revenue vs the snapshot
--   B. keys                              one row per subscriber
--   C. location coverage                 most-used cell site found, site found in the site master
--   D. 5G flag consistency               5G users have a 5G device, flags match the shared view
--   E. month-over-month drift            active base and 5G-user share vs last month
------------------------------------------------------------------------------------------

------------------------------------------------------------------------------------------
-- RUN DATE
------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS TEMP_DQ_DATE;

CREATE LOCAL TEMP TABLE TEMP_DQ_DATE ON COMMIT PRESERVE ROWS AS
(
SELECT GREG_MTH_ID AS MNTH_ID
, CAST(TO_CHAR(ADD_MONTHS(TO_DATE(CAST(GREG_MTH_ID AS VARCHAR(6)), 'YYYYMM'), -1), 'YYYYMM') AS INT) AS PREV_MNTH_ID
FROM EDW2.GEOG_CLDR
WHERE GREG_MTH_ID = :RUN_MNTH
GROUP BY 1
)
SEGMENTED BY HASH(MNTH_ID) ALL NODES
;

------------------------------------------------------------------------------------------
-- SOURCE: RUN MONTH + LAST MONTH OF THE SNAPSHOT, DEDUPLICATED THE SAME WAY AS 02
------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS TEMP_DQ_SNP;

CREATE LOCAL TEMP TABLE TEMP_DQ_SNP ON COMMIT PRESERVE ROWS AS
(
SELECT A.MNTH_ID
, A.SUBR_ID
, A.ACTV_CITRINE_FLG
, COALESCE(A.CLT_REVN_AF_SHRE_PP, 0) + COALESCE(A.REVN_BILL, 0) AS REVN_AMNT
FROM EDW2.SNP_MNTH_SUBR_ANLS A
WHERE A.MNTH_ID IN (SELECT MNTH_ID FROM TEMP_DQ_DATE UNION ALL SELECT PREV_MNTH_ID FROM TEMP_DQ_DATE)
AND A.SBSCRPN_CLASS_CD NOT IN ('V', 'S')
LIMIT 1 OVER (PARTITION BY MNTH_ID, SUBR_ID ORDER BY MOST_USED_4W_CELL_SITE DESC)
)
SEGMENTED BY HASH(MNTH_ID, SUBR_ID) ALL NODES
;

------------------------------------------------------------------------------------------
-- RUN ALL CHECKS
------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS TEMP_DQ_RESULT;

CREATE LOCAL TEMP TABLE TEMP_DQ_RESULT ON COMMIT PRESERVE ROWS AS
(
-- A1. subscribers: profile = snapshot
SELECT 'A1' AS CHECK_NO
, 'Subscribers: profile vs snapshot' AS CHECK_NAME
, T.N AS ACTUAL
, S.N AS EXPECTED
, CASE WHEN T.N = S.N THEN 'PASS' ELSE 'FAIL' END AS STATUS
FROM (SELECT COUNT(DISTINCT SUBR_ID) AS N FROM SANDBOX2.AUTO_5G_PROFILE WHERE MNTH_ID IN (SELECT MNTH_ID FROM TEMP_DQ_DATE)) T
CROSS JOIN (SELECT COUNT(*) AS N FROM TEMP_DQ_SNP WHERE MNTH_ID IN (SELECT MNTH_ID FROM TEMP_DQ_DATE)) S

UNION ALL
-- A2. active base: profile = snapshot
SELECT 'A2', 'Active citrine subscribers: profile vs snapshot'
, T.N, S.N
, CASE WHEN T.N = S.N THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT SUM(ACTV_CITRINE_NSUBR) AS N FROM SANDBOX2.AUTO_5G_PROFILE WHERE MNTH_ID IN (SELECT MNTH_ID FROM TEMP_DQ_DATE)) T
CROSS JOIN (SELECT SUM(CASE WHEN ACTV_CITRINE_FLG = 'Y' THEN 1 ELSE 0 END) AS N FROM TEMP_DQ_SNP WHERE MNTH_ID IN (SELECT MNTH_ID FROM TEMP_DQ_DATE)) S

UNION ALL
-- A3. revenue KPI: profile = snapshot (rounding tolerance 0.01%)
SELECT 'A3', 'Revenue total: profile vs snapshot'
, T.R, S.R
, CASE WHEN ABS(T.R - S.R) <= 0.0001 * ABS(S.R) THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT SUM(REVN_AMNT) AS R FROM SANDBOX2.AUTO_5G_PROFILE WHERE MNTH_ID IN (SELECT MNTH_ID FROM TEMP_DQ_DATE)) T
CROSS JOIN (SELECT SUM(REVN_AMNT) AS R FROM TEMP_DQ_SNP WHERE MNTH_ID IN (SELECT MNTH_ID FROM TEMP_DQ_DATE)) S

UNION ALL
-- B1. one row per subscriber (a duplicate would double count users and revenue in every extract)
SELECT 'B1', 'Subscribers with more than one profile row'
, COUNT(*), 0
, CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (
    SELECT SUBR_ID FROM SANDBOX2.AUTO_5G_PROFILE
    WHERE MNTH_ID IN (SELECT MNTH_ID FROM TEMP_DQ_DATE)
    GROUP BY SUBR_ID HAVING COUNT(*) > 1
) X

UNION ALL
-- C1. active subscribers with no most-used cell site (they drop out of the location analysis)
SELECT 'C1', '% active subscribers with no most-used cell site (<= 5%)'
, ROUND(100.0 * SUM(CASE WHEN STD_SITE_REF IS NULL THEN ACTV_CITRINE_NSUBR ELSE 0 END) / NULLIF(SUM(ACTV_CITRINE_NSUBR), 0), 2), 5
, CASE WHEN 100.0 * SUM(CASE WHEN STD_SITE_REF IS NULL THEN ACTV_CITRINE_NSUBR ELSE 0 END) / NULLIF(SUM(ACTV_CITRINE_NSUBR), 0) <= 5 THEN 'PASS' ELSE 'FAIL' END
FROM SANDBOX2.AUTO_5G_PROFILE
WHERE MNTH_ID IN (SELECT MNTH_ID FROM TEMP_DQ_DATE)

UNION ALL
-- C2. site found in the site master (else SUPPORT_SITE_5G stays NULL and the site is neither "covered" nor "not covered")
SELECT 'C2', '% subscribers with a site but no 5G-coverage flag (<= 1%)'
, ROUND(100.0 * SUM(CASE WHEN SUPPORT_SITE_5G IS NULL THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2), 1
, CASE WHEN 100.0 * SUM(CASE WHEN SUPPORT_SITE_5G IS NULL THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) <= 1 THEN 'PASS' ELSE 'FAIL' END
FROM SANDBOX2.AUTO_5G_PROFILE
WHERE MNTH_ID IN (SELECT MNTH_ID FROM TEMP_DQ_DATE)
AND STD_SITE_REF IS NOT NULL

UNION ALL
-- D1. 5G traffic without a 5G device points to a device-master gap
SELECT 'D1', '% of 5G users without a 5G-device flag (<= 1%)'
, ROUND(100.0 * SUM(CASE WHEN DVC_SUPPORT_FLAG = '-' THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2), 1
, CASE WHEN 100.0 * SUM(CASE WHEN DVC_SUPPORT_FLAG = '-' THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) <= 1 THEN 'PASS' ELSE 'FAIL' END
FROM SANDBOX2.AUTO_5G_PROFILE
WHERE MNTH_ID IN (SELECT MNTH_ID FROM TEMP_DQ_DATE)
AND USAGE_5G_FLAG = '5G Usage'

UNION ALL
-- D2. profile flags = shared view (01 and 02 must report the same 5G users)
SELECT 'D2', 'Subscribers whose 5G flags differ from V_5G_SUBR_FLAG_MNTH'
, COUNT(*), 0
, CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM SANDBOX2.AUTO_5G_PROFILE P
INNER JOIN SANDBOX2.V_5G_SUBR_FLAG_MNTH V
ON P.SUBR_ID = V.SUBR_ID
AND P.MNTH_ID = V.MNTH_ID
WHERE P.MNTH_ID IN (SELECT MNTH_ID FROM TEMP_DQ_DATE)
AND (   P.DVC_SUPPORT_FLAG     <> V.DVC_SUPPORT_FLAG
     OR P.PROVISIONING_5G_FLAG <> V.PROVISIONING_5G_FLAG
     OR P.USAGE_5G_FLAG        <> V.USAGE_5G_FLAG)

UNION ALL
-- E1. active base vs last month (+/-5%)
SELECT 'E1', 'Active citrine: % change vs last month (+/-5%)'
, ROUND(100.0 * (C.N - P.N) / NULLIF(P.N, 0), 2), 5
, CASE WHEN P.N > 0 AND ABS(100.0 * (C.N - P.N) / P.N) <= 5 THEN 'PASS' ELSE 'FAIL' END
FROM       (SELECT SUM(CASE WHEN ACTV_CITRINE_FLG = 'Y' THEN 1 ELSE 0 END) AS N FROM TEMP_DQ_SNP WHERE MNTH_ID IN (SELECT MNTH_ID      FROM TEMP_DQ_DATE)) C
CROSS JOIN (SELECT SUM(CASE WHEN ACTV_CITRINE_FLG = 'Y' THEN 1 ELSE 0 END) AS N FROM TEMP_DQ_SNP WHERE MNTH_ID IN (SELECT PREV_MNTH_ID FROM TEMP_DQ_DATE)) P

UNION ALL
-- E2. 5G-user share of the active base vs last month (+/-3pp) - a sudden move is more often a feed / network change than behaviour
SELECT 'E2', '5G-user share of active base: change vs last month in pp (+/-3)'
, ROUND(C.PCT - P.PCT, 2), 3
, CASE WHEN ABS(C.PCT - P.PCT) <= 3 THEN 'PASS' ELSE 'FAIL' END
FROM (
    SELECT 100.0 * SUM(CASE WHEN V.USAGE_5G_FLAG = '5G Usage' THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) AS PCT
    FROM TEMP_DQ_SNP S
    INNER JOIN SANDBOX2.V_5G_SUBR_FLAG_MNTH V ON S.SUBR_ID = V.SUBR_ID AND S.MNTH_ID = V.MNTH_ID
    WHERE S.MNTH_ID IN (SELECT MNTH_ID FROM TEMP_DQ_DATE) AND V.MNTH_ID IN (SELECT MNTH_ID FROM TEMP_DQ_DATE)
    AND S.ACTV_CITRINE_FLG = 'Y'
) C
CROSS JOIN (
    SELECT 100.0 * SUM(CASE WHEN V.USAGE_5G_FLAG = '5G Usage' THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) AS PCT
    FROM TEMP_DQ_SNP S
    INNER JOIN SANDBOX2.V_5G_SUBR_FLAG_MNTH V ON S.SUBR_ID = V.SUBR_ID AND S.MNTH_ID = V.MNTH_ID
    WHERE S.MNTH_ID IN (SELECT PREV_MNTH_ID FROM TEMP_DQ_DATE) AND V.MNTH_ID IN (SELECT PREV_MNTH_ID FROM TEMP_DQ_DATE)
    AND S.ACTV_CITRINE_FLG = 'Y'
) P
)
;

------------------------------------------------------------------------------------------
-- RESULT
------------------------------------------------------------------------------------------
SELECT * FROM TEMP_DQ_RESULT ORDER BY CHECK_NO;

SELECT (SELECT MNTH_ID FROM TEMP_DQ_DATE) AS MNTH_ID
, COUNT(*) AS CHECKS
, SUM(CASE WHEN STATUS = 'FAIL' THEN 1 ELSE 0 END) AS FAILED
, CASE WHEN SUM(CASE WHEN STATUS = 'FAIL' THEN 1 ELSE 0 END) = 0 THEN 'OK TO PUBLISH' ELSE 'HOLD - CHECK FAILED ROWS' END AS RESULT
FROM TEMP_DQ_RESULT
;
