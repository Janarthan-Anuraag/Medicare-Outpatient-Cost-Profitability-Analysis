CREATE TABLE outpatient_data (
    Rndrng_Prvdr_CCN VARCHAR,
    Rndrng_Prvdr_Org_Name TEXT,
    Rndrng_Prvdr_St TEXT,
    Rndrng_Prvdr_City TEXT,
    Rndrng_Prvdr_State_Abrvtn VARCHAR(2),
    Rndrng_Prvdr_State_FIPS VARCHAR,
    Rndrng_Prvdr_Zip5 VARCHAR(5),
    Rndrng_Prvdr_RUCA TEXT,
    Rndrng_Prvdr_RUCA_Desc TEXT,
    APC_Cd VARCHAR,
    APC_Desc TEXT,
    Bene_Cnt INTEGER,
    CAPC_Srvcs INTEGER,
    Avg_Tot_Sbmtd_Chrgs NUMERIC,
    Avg_Mdcr_Alowd_Amt NUMERIC,
    Avg_Mdcr_Pymt_Amt NUMERIC,
    Outlier_Srvcs INTEGER,
    Avg_Mdcr_Outlier_Amt NUMERIC
);

SELECT COUNT(*) FROM outpatient_data;
SELECT * FROM outpatient_data LIMIT 5;

--Top 10 Most Frequently Billed Procedures


SELECT 
    apc_cd,
    apc_desc,
   SUM(capc_srvcs) AS total_services
FROM outpatient_data
WHERE capc_srvcs IS NOT NULL
GROUP BY apc_cd, apc_desc
ORDER BY total_services DESC
LIMIT 10;

--Top 10 Most Expensive Procedures (by Average Charges)

SELECT 
    apc_cd,
    apc_desc,
    ROUND(AVG(avg_tot_sbmtd_chrgs), 2) AS avg_charge
FROM outpatient_data
WHERE capc_srvcs >= 100
GROUP BY apc_cd, apc_desc
ORDER BY avg_charge DESC
LIMIT 10;

-- Average Cost by State

SELECT 
    rndrng_prvdr_state_abrvtn AS state,
    ROUND(AVG(avg_tot_sbmtd_chrgs), 2) AS avg_state_charge
FROM outpatient_data
GROUP BY state
ORDER BY avg_state_charge DESC;

--Outlier Hospitals (Charge vs. State Average) 

WITH state_procedure_avg AS (
    SELECT 
        rndrng_prvdr_state_abrvtn AS state,
        apc_cd,
        AVG(avg_tot_sbmtd_chrgs) AS avg_state_charge
    FROM outpatient_data
    WHERE avg_tot_sbmtd_chrgs IS NOT NULL
    GROUP BY state, apc_cd
)

SELECT 
    o.rndrng_prvdr_org_name,
    o.rndrng_prvdr_city,
    o.rndrng_prvdr_state_abrvtn,
    o.apc_cd,
    o.apc_desc,
    o.avg_tot_sbmtd_chrgs,
    s.avg_state_charge,
    ROUND(o.avg_tot_sbmtd_chrgs - s.avg_state_charge, 2) AS charge_diff
FROM outpatient_data o
JOIN state_procedure_avg s 
  ON o.rndrng_prvdr_state_abrvtn = s.state
 AND o.apc_cd = s.apc_cd
WHERE o.avg_tot_sbmtd_chrgs > s.avg_state_charge + 2000
ORDER BY charge_diff DESC
LIMIT 25;

--Ranking Providers Within Each State by Charge
--This shows: --Top-charging providers per procedure in each state
              --RANK() resets per state + procedure (PARTITION BY)
              --Filters for providers who billed at least 50 times, avoiding low-volume noise


SELECT
    rndrng_prvdr_state_abrvtn AS state,
    rndrng_prvdr_org_name AS provider,
    apc_cd,
    apc_desc,
    avg_tot_sbmtd_chrgs,
    RANK() OVER (
        PARTITION BY rndrng_prvdr_state_abrvtn, apc_cd
        ORDER BY avg_tot_sbmtd_chrgs DESC
    ) AS provider_rank_within_state
FROM outpatient_data
WHERE capc_srvcs > 50
ORDER BY state, apc_cd, provider_rank_within_state
LIMIT 100;


--Categorizing Procedures by Cost Level--
--This will let you group procedures into low, moderate, and high-cost tiers — an input for Tableau dashboards and business reporting
--from this table we can see that in The top 30 billed outpatient procedures by average charge are all classified as ‘High Cost.’ 
--This concentration highlights the need for focused cost-containment strategies around a small set of procedures that disproportionately impact Medicare billing and payment
SELECT
    apc_cd,
    apc_desc,
    ROUND(AVG(avg_tot_sbmtd_chrgs), 2) AS avg_charge,
    CASE 
        WHEN AVG(avg_tot_sbmtd_chrgs) < 500 THEN 'Low Cost'
        WHEN AVG(avg_tot_sbmtd_chrgs) BETWEEN 500 AND 1500 THEN 'Moderate Cost'
        ELSE 'High Cost'
    END AS cost_category,
    COUNT(*) AS num_providers
FROM outpatient_data
WHERE avg_tot_sbmtd_chrgs IS NOT NULL
GROUP BY apc_cd, apc_desc
ORDER BY avg_charge DESC
LIMIT 30;



--Most Profitable Procedures--

--Difference between what hospitals charge vs. what Medicare actually pays — averaged across providers.

--While CMS data does not include provider cost data, the large and persistent gaps between submitted charges and Medicare payments in high-volume procedures may suggest opportunities for price transparency reform or payment standardization.

SELECT 
    apc_cd,
    apc_desc,
    ROUND(AVG(avg_tot_sbmtd_chrgs - avg_mdcr_pymt_amt), 2) AS avg_margin,
    ROUND(AVG(avg_tot_sbmtd_chrgs), 2) AS avg_charge,
    ROUND(AVG(avg_mdcr_pymt_amt), 2) AS avg_payment,
    SUM(capc_srvcs) AS total_services
FROM outpatient_data
WHERE avg_tot_sbmtd_chrgs IS NOT NULL 
  AND avg_mdcr_pymt_amt IS NOT NULL 
  AND capc_srvcs > 100
GROUP BY apc_cd, apc_desc
ORDER BY avg_margin DESC
LIMIT 20;

--For Tableau Dashboard:--

--Dataset 1: State-Level Average Charges

SELECT 
    rndrng_prvdr_state_abrvtn AS state,
    apc_cd,
    apc_desc,
    ROUND(AVG(avg_tot_sbmtd_chrgs), 2) AS avg_charge,
    ROUND(AVG(avg_mdcr_pymt_amt), 2) AS avg_payment,
    COUNT(*) AS num_providers,
    SUM(capc_srvcs) AS total_services
FROM outpatient_data
WHERE avg_tot_sbmtd_chrgs IS NOT NULL
GROUP BY state, apc_cd, apc_desc;

--Dataset 2: Procedure Profitability by State

SELECT 
    rndrng_prvdr_state_abrvtn AS state,
    apc_desc,
    ROUND(AVG(avg_tot_sbmtd_chrgs), 2) AS avg_charge,
    ROUND(AVG(avg_mdcr_pymt_amt), 2) AS avg_payment,
    ROUND(AVG(avg_tot_sbmtd_chrgs - avg_mdcr_pymt_amt), 2) AS avg_margin,
    SUM(capc_srvcs) AS total_services
FROM outpatient_data
WHERE avg_tot_sbmtd_chrgs IS NOT NULL
GROUP BY state, apc_desc;





