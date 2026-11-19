------------------------------------------------------------------------------------------
-- 5G FLAGS PER SUBSCRIBER PER MONTH - ONE DEFINITION FOR ALL 5G REPORTS
--   used by 01_high_value_report_5g_parameter.sql and 02_5g_profile_cell_site_prioritisation.sql
--   (both scripts used to repeat this logic - 4 copies - so a rule change had to be made 4 times)
--
--   DVC_SUPPORT_FLAG      handset supports 5G
--   PROVISIONING_5G_FLAG  "5G Provisioning" package active on the last day of the month
--   USAGE_5G_FLAG         any data used on 5G in the month
--
--   one row per MNTH_ID x SUBR_ID (the snapshot can hold duplicate rows per subscriber)
--   always query with a MNTH_ID filter
--   create once, re-run only when a rule changes
------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW SANDBOX2.V_5G_SUBR_FLAG_MNTH AS

SELECT A.MNTH_ID
, A.SUBR_ID
, CASE WHEN MAX(CASE WHEN A.DVC_SUPPORT LIKE '%5G%' THEN 1 ELSE 0 END) = 1 THEN '5G Device Support' ELSE '-' END AS DVC_SUPPORT_FLAG
, CASE WHEN MAX(CASE WHEN P.SUBR_ID IS NOT NULL      THEN 1 ELSE 0 END) = 1 THEN '5G Provisioning'   ELSE '-' END AS PROVISIONING_5G_FLAG
, CASE WHEN MAX(CASE WHEN A.DATA_MB_5G_VOL > 0       THEN 1 ELSE 0 END) = 1 THEN '5G Usage'          ELSE '-' END AS USAGE_5G_FLAG

FROM EDW2.SNP_MNTH_SUBR_ANLS AS A
LEFT OUTER JOIN
(
    -- 5G provisioning package active on the last day of each month
    SELECT C.MNTH_ID
    , K.SUBR_ID
    FROM EDW2.DIM_PKG_SPLMNTRY_MERG K
    INNER JOIN
    (
        SELECT GREG_MTH_ID AS MNTH_ID
        , MAX(GREG_DT_DT) AS MAX_RUN_DATE
        FROM EDW2.GEOG_CLDR
        GROUP BY 1
    ) C
    ON C.MAX_RUN_DATE BETWEEN CAST(K.PKG_START_DT AS DATE) AND CAST(K.PKG_END_DT AS DATE)
    WHERE UPPER(K.PKG_NM) LIKE '5G PROVISIONING%'
    GROUP BY 1, 2
) AS P
ON A.SUBR_ID = P.SUBR_ID
AND A.MNTH_ID = P.MNTH_ID

GROUP BY 1, 2
;
