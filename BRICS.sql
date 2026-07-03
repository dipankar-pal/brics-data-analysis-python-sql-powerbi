USE BRICS;

-------EXPLORE THE DATA
SELECT * FROM [dbo].[brics_world_bank];

--- FOR DELETE
DROP TABLE brics_world_bank;

---CHACK TOP 10 ROWS
SELECT TOP 10 *
FROM dbo.brics_world_bank;

---How many rows?
SELECT COUNT(*) AS total_rows
FROM dbo.brics_world_bank;  

---HOW MANY ROWS PER COUNTRY
SELECT 
     [country_name],
	 COUNT(*) as total_rows
FROM [dbo].[brics_world_bank]
GROUP BY country_name
ORDER BY country_name;


---WHAT YEARS  ARE IN THE DATA
SELECT
     MIN(year) AS FIRST_YEAR,
	 MAX(year) AS LAST_YEAR,
	 COUNT(DISTINCT year) AS TOTAL_YEARS
FROM [dbo].[brics_world_bank];

---======================================================================================================================================================================
-----------------------CREATE VIEW FOR ANALYSIS AND visualization---------------------------------------
CREATE VIEW brics_world_bank_data  as
SELECT
    country_name,
    year,
    ROUND(gdp_usd / 1e12, 2) AS gdp_trillion_usd,
    ROUND(gdp_per_capita, 0) AS gdp_per_person_usd,
    ROUND(gdp_growth_pct, 2) AS gdp_growth_pct,
    ROUND(population / 1e9, 2) AS population_billion,
    ROUND(life_expectancy, 1) AS life_expectancy,
    ROUND(inflation_pct, 2) AS inflation_pct,
    ROUND(unemployment_pct, 2) AS unemployment_pct,
    ROUND(exports_usd / 1e9, 1) AS exports_billion,
    ROUND(imports_usd / 1e9, 1) AS imports_billion,
    ROUND(trade_pct_gdp, 1) AS trade_pct_gdp,
    ROUND(fdi_inflows_usd / 1e9, 2) AS fdi_billion,
    ROUND(debt_pct_gdp, 1) AS debt_pct_gdp,
    ROUND(internet_users_pct, 1) AS internet_users_pct,
    --ROUND(co2_per_capita, 2) AS co2_per_person,
    ROUND(health_expenditure_pct_gdp, 2) AS health_spend_pct_gdp
FROM [dbo].[brics_world_bank]
;

--chack
select * from brics_world_bank_data;
--==================================================================================================================================================================
---------------------------------------------------------------------

------------------***GDP ANALYSIS***----------------------

--GDP = "TOTAL MONEY A COUNTRY EARNS IN ONE YEAR"

--(1) Who is the richest BRICS country today?
--LATEST GDP FOR EACH COUNTRY (MOST RECENT YEAR)

SELECT 
      country_name,
	  year,
	  ROUND(gdp_usd /1e12, 2) AS GDP_TRILLION_USD,
	  ROUND([gdp_per_capita], 0) AS GDP_PER_PERSON_USD,
	  ROUND([gdp_growth_pct], 2) AS GDP__GROWTH_PCT
FROM [dbo].[brics_world_bank]
WHERE 
      year = (
	            SELECT MAX(year) 
	               FROM  brics_world_bank
				WHERE
				      gdp_usd >0
			  )
AND  gdp_usd >0
ORDER BY gdp_usd DESC;


---(2) HOW DID EACH COUNTRY GROW OVER 24 YEARS ?
--GDP TREND OVER YEARS - ALL COUNTRIES

SELECT 
      [country_name],
      [year],
	  ROUND(gdp_usd /1e12, 2) AS GDP_TRILLION_USD
FROM brics_world_bank
WHERE 
     gdp_usd > 0
ORDER BY
     1,2;

---(3) WHICH COUNTRY WAS #1 IN GDP EACH YEAR ?
--GDP RANK PER YEAR USING RANK()

SELECT 
     [year],
	 [country_name],
	 ROUND(gdp_usd /1e12, 2) AS GDP_TRILLION_USD,
	 RANK() OVER (PARTITION BY year 
	                ORDER BY gdp_usd DESC) AS GDP_RANK
FROM 
     brics_world_bank
WHERE 
     gdp_usd > 0
ORDER BY 
     1,4;

---(4) WHICH YEAR HAD THE BEST GDP JUMP ? 
--YEAR-OVER-YEAR GDP GROWTH USING LAG()
SELECT 
      [country_name],
      year,
	  ROUND(gdp_usd /1e12, 2) AS GDP_TRILLION_USD,
	  ROUND(
	        LAG(gdp_usd)OVER(PARTITION BY country_name 
			                        ORDER BY year
						  ) / 1e12,
						            2 ) AS prev_year_gdp_trillion,
	 CONCAT(ROUND((gdp_usd - LAG(gdp_usd)OVER(PARTITION BY country_name ORDER BY year)) 
	             * 100
				 / NULLIF(LAG(gdp_usd) OVER (
            PARTITION BY country_name ORDER BY year
        ), 0), 2),' %') AS yoy_growth_pct
FROM brics_world_bank
WHERE gdp_usd > 0
ORDER BY 
       [country_name],
      year;

---(5) WHICH COUNTRY MULTTIPLIED GDP THE MOST?
--How much did each country grow from 2000 to latest? 
WITH GDP_START AS (
SELECT 
      [country_name],
      [gdp_usd] AS GDP_START,
	  year  AS FIRST_YEAR
FROM brics_world_bank
WHERE gdp_usd > 0
      AND
      year = (
	           SELECT MIN(year) 
			   FROM brics_world_bank
			   WHERE gdp_usd > 0
			   )
),
GDP_LATEST AS (
SELECT 
      [country_name],
      [gdp_usd] AS GDP_LATEST,
	  [year] AS LAST_YEAR
FROM  brics_world_bank
WHERE gdp_usd > 0
      AND
	  year = (
	           SELECT  MAX(year)
			   FROM brics_world_bank
			   WHERE gdp_usd > 0
			   )
)
SELECT 
      G2.country_name,
	  ROUND(G1.GDP_START  /  1e12, 2) AS GDP_START_TRILLION,
	  ROUND(G2.GDP_LATEST  / 1e12, 2) AS GDP_LATEST_TRILLION,
	  ROUND(G2.GDP_LATEST  /  G1.GDP_START, 1) AS GROWTH_MULTIPLIER,
	  CONCAT(ROUND((G2.GDP_LATEST  - G1.GDP_START) * 100  /  G1.GDP_START, 1), ' %') AS TOTAL_GROWTH_PCT
FROM GDP_LATEST AS G2
JOIN GDP_START AS G1
ON
   G2.country_name = G1.country_name
ORDER BY 3;


---==========================================================================================================================================================================

-------------------------------POPULATION ANALYSIS------------------------------

---(1) CURRENT POPULATION OF EACH COUNTRY

SELECT 
     [country_name],
     [year],
     CONCAT(ROUND([population] / 1e9, 2 ), ' b') AS POPULATION_BILLION,
     CONCAT(ROUND([population_growth_pct], 2), ' %') AS population_growth_pct
FROM brics_world_bank
WHERE 
     year = (
	 SELECT MAX(year) AS LATEST_YEAR FROM brics_world_bank)
ORDER BY 3 DESC;

---(2) WHO IS GROWING FASTEST ?
--POPULATION GROWTH TREND (2000 - LATEST) 

SELECT
    country_name,
    year,
-- Current population
    ROUND(population / 1e6, 1)
        AS population_million,
-- Previous period population (5 years ago)
    ROUND(
        LAG(population) OVER (
            PARTITION BY country_name
            ORDER BY year
        ) / 1e6, 1
    ) AS prev_period_million,
-- How many million people added in 5 years?
    ROUND(
        (population -
            LAG(population) OVER (
                PARTITION BY country_name
                ORDER BY year
            )
        ) / 1e6, 1
    ) AS added_million_people
FROM dbo.brics_world_bank
WHERE population > 0
  AND year IN (2000, 2005, 2010, 2015, 2020, 2024)
ORDER BY 
       country_name,
	   year;

---(3) GDP PER CAPITA (AVERAGE INCOME PER PERSON)

SELECT 
      [country_name],
      [year],
      ROUND([gdp_per_capita], 1) AS gdp_per_capita,
	  RANK() OVER (PARTITION BY year 
	                  ORDER BY gdp_per_capita DESC) AS WEALTH_RANK
FROM 
      brics_world_bank
WHERE 
      year IN (2000, 2005, 2010, 2015, 2020, 2024)
ORDER BY 
      2,
	  4;

--=====================================================================================================================================================
---------------------------TRADE ANALYSIS-----------------------------
--------------------------(EXPORT + IMPORT)---------------------------------

--(1) LATEST TRADE NUMBERS

SELECT 
      [country_name],
      [year],
      ROUND([exports_usd] / 1e9, 1) AS exports_usd_BILLION,
      ROUND([imports_usd] / 1e9, 1) AS imports_usd_BILLION,
	  ROUND(([exports_usd] - [imports_usd]) / 1e9, 1) AS TRADE_BALANCE_BILLION,
	  CASE
	      WHEN exports_usd > imports_usd THEN 'TRADE SURPLUS'
		  WHEN exports_usd < imports_usd THEN 'TRADE DEFICIT'
		  ELSE 'BALANCED'
	  END AS TRADE_STATUS
FROM 
      brics_world_bank
WHERE 
      year = (SELECT MAX(year) FROM  brics_world_bank
			          WHERE [exports_usd] > 0 )
AND
     [exports_usd] > 0
ORDER BY  5 DESC;

---(2) TRADE AS % OF GDP OVER TIME
--# A HIGH % MEANS THE COUNTRY DEPENDS HEAVILY ON THE TRADE

SELECT 
      [country_name],
      [year],
      ROUND([trade_pct_gdp],2) AS trade_pct_gdp,
	  RANK()OVER(PARTITION BY year ORDER BY trade_pct_gdp DESC) AS TRADE_RANK
FROM brics_world_bank
WHERE trade_pct_gdp > 0
ORDER BY year, trade_pct_gdp DESC


---(3) Which country is the most trade-dependent?
--(2000-2024)

SELECT
    country_name,
    ROUND(AVG(trade_pct_gdp), 1) AS avg_trade_pct_gdp,
    ROUND(MIN(trade_pct_gdp), 1) AS min_trade_pct,
    ROUND(MAX(trade_pct_gdp), 1) AS max_trade_pct
FROM 
    dbo.brics_world_bank
WHERE 
    trade_pct_gdp > 0
GROUP BY 
    country_name
ORDER BY 
    avg_trade_pct_gdp DESC;

--============================================================================================================================================================
------------------------UNEMPLOYMENT  &  INFLATION-------------------------------

--(1) UNEMPLOYMENT TREND (#Looking for a job but don't have one)
SELECT
     [country_name],
     [year],
     ROUND([unemployment_pct], 2) AS unemployment_pct,
	 RANK()OVER(PARTITION BY year ORDER BY unemployment_pct DESC) AS UNEMPLOY_RANK
FROM 
     brics_world_bank

-----(2)Latest inflation rate per country (#more expensive life has become in a country)

SELECT 
      [country_name],
      [year],
      ROUND([inflation_pct],2) AS inflation_pct,
	  RANK()OVER(PARTITION BY year ORDER BY inflation_pct DESC) AS RANK_OF_inflation_pct
FROM 
      brics_world_bank
WHERE 
     year = (SELECT MAX(year) FROM brics_world_bank );


--(3) AVG inflation PER COUNTRY OVER ALL YEARS (2000- LATEST YEAR)

SELECT 
      [country_name],
	ROUND(AVG([inflation_pct]), 2) AS AVG_inflation,
	ROUND(MAX([inflation_pct]), 2) AS MAX_inflation,
	ROUND(MIN([inflation_pct]), 2) AS MIN_inflation
FROM brics_world_bank
GROUP BY [country_name]
ORDER BY 2 DESC;

--====================================================================================================================================================================
---------------------- FDI (FOREIGN DIRECT INVESTMENT)--------------

--(1) Which BRICS country has been the most successful in attracting foreign investment, both recently and over the long term?
WITH latest_year AS
(
    SELECT MAX(year) AS latest_year
    FROM dbo.brics_world_bank
    WHERE fdi_inflows_usd > 0
)
SELECT
    b.country_name,
    ROUND(
        MAX(CASE
                WHEN b.year = ly.latest_year
                THEN b.fdi_inflows_usd
            END) / 1e9, 2
    ) AS latest_fdi_billion,

    ROUND(SUM(b.fdi_inflows_usd) / 1e9, 1)
        AS total_fdi_billion,
    ROUND(AVG(b.fdi_inflows_usd) / 1e9, 1)
        AS avg_fdi_per_year_billion,
    DENSE_RANK() OVER(
        ORDER BY SUM(b.fdi_inflows_usd) DESC
    ) AS fdi_rank,

    CASE
        WHEN SUM(b.fdi_inflows_usd) >=
             (SELECT AVG(total_fdi)
              FROM
              (
                  SELECT SUM(fdi_inflows_usd) total_fdi
                  FROM dbo.brics_world_bank
                  WHERE fdi_inflows_usd > 0
                  GROUP BY country_name
              ) x)                                             --x = temporary table name
        THEN 'High Investment Attraction'
        ELSE 'Moderate Investment Attraction'
    END AS investment_insight

FROM dbo.brics_world_bank b
CROSS JOIN latest_year ly
WHERE b.fdi_inflows_usd > 0
GROUP BY b.country_name
ORDER BY total_fdi_billion DESC;


---=====================================================================================================================================================================
---------------------------HEALTH ANALYSIS---------------------------------------------------

--Life expectancy = average age people live to
--Health spending = how much govt spends on hospitals, doctors.

--(1) Life expectancy comparison (latest year)
SELECT 
      [country_name],
	  [year],
      ROUND([life_expectancy],  2) AS life_expectancy
FROM 
      brics_world_bank
WHERE 
      year = (SELECT MAX(year) FROM brics_world_bank)            
ORDER BY life_expectancy DESC

-- (2) How much did governments spend on healthcare as a percentage of GDP (2018–2023)?
-- Note: 2024 data is unavailable for health_expenditure_pct_gdp.

SELECT 
      [country_name],
	  [year],
      ROUND([health_expenditure_pct_gdp],  2) AS health_expenditure,
	  RANK()OVER(PARTITION BY year ORDER BY [health_expenditure_pct_gdp]DESC) AS RANK_health_expenditure
FROM brics_world_bank
WHERE 
      year BETWEEN 2018 AND 2023   

---NOW ONLY FOR  2023
SELECT 
      [country_name],
	  [year],
      ROUND([health_expenditure_pct_gdp],  2) AS health_expenditure,
	  RANK()OVER(PARTITION BY year ORDER BY [health_expenditure_pct_gdp]DESC) AS RANK_health_expenditure
FROM brics_world_bank
WHERE 
      year = 2023 

-- NOW FOR OVER ALL
SELECT 
      [country_name],
      ROUND(AVG([health_expenditure_pct_gdp]),  2) AS AVG_health_expenditure,
	  ROUND(MIN([health_expenditure_pct_gdp]),  2) AS MIN_health_expenditure,
	  ROUND(MAX([health_expenditure_pct_gdp]),  2) AS MAX_health_expenditure,
	  RANK()OVER(ORDER BY AVG([health_expenditure_pct_gdp])DESC) AS RANK_health_expenditure
FROM brics_world_bank
WHERE 
       year BETWEEN 2000 AND 2023
GROUP BY country_name;

--(3) LIFE EXPECTANCY IMPROVE OVER 24 YEARS?
-- Compare 2000 vs latest for each country

WITH life_2000 AS (
    SELECT 
		country_name, 
		life_expectancy AS life_2000
    FROM dbo.brics_world_bank
    WHERE 
	    year = (SELECT MIN(year) FROM dbo.brics_world_bank )
),
life_now AS (
    SELECT 
		country_name, 
		life_expectancy AS life_now
    FROM dbo.brics_world_bank
    WHERE year = (SELECT MAX(year) FROM dbo.brics_world_bank )
)
SELECT
    L2.country_name,
    ROUND(L2.life_2000, 1)                        AS life_exp_2000,
    ROUND(LN.life_now, 1)                         AS life_exp_now,
    ROUND(LN.life_now - L2.life_2000, 1)          AS years_gained
FROM life_2000 L2
JOIN life_now LN 
ON L2.country_name = LN.country_name
ORDER BY years_gained DESC;


--==================================================================================================================================================================
--------------------------------TECHNOLOGY — INTERNET USERS---------------------------------
--Internet users % = how many people use internet. This shows digital growth of the country.

--(1) INTERNET USERS (LATEST YEAR)
SELECT 
      [country_name],
      [year],
	  ROUND([internet_users_pct], 2) AS internet_users_pct,
	  CASE 
	      WHEN internet_users_pct >= 70 THEN 'Digitally Advanced'
		  WHEN internet_users_pct >= 60 THEN 'Growing Digital'
		  WHEN internet_users_pct >= 50 THEN 'Early Stage'
	      ELSE 'VERY LOW'
	  END AS DIGITAL_STATUS
FROM 
    brics_world_bank
WHERE year = (SELECT MAX(year) FROM dbo.brics_world_bank )
ORDER BY 3 DESC;

--(2) Which BRICS country experienced the highest percentage growth in internet users over the last 10 years?

WITH LATEST_YEAR AS (
SELECT 
      [country_name],
      [year],
      ROUND([internet_users_pct], 2) AS internet_users_pct
FROM 
    brics_world_bank
WHERE year = (SELECT MAX(year) FROM dbo.brics_world_bank )
),
D_10_YEAR_AGO AS (
SELECT 
      [country_name],
      [year],
      ROUND([internet_users_pct], 2) AS internet_users_pct
FROM 
    brics_world_bank
WHERE year = ((SELECT MAX(year) FROM dbo.brics_world_bank ) - 10)
)

SELECT
      LY.country_name,
	  LY.internet_users_pct        AS LATEST_YEAR_internet_users_pct,
	  D10Y.internet_users_pct       AS TEN_YEAR_AGO_internet_users_pct,
	  ROUND((LY.internet_users_pct  -  D10Y.internet_users_pct) * 100 / D10Y.internet_users_pct, 2)  AS PCT_OF_INTERNET_USER_GROWTH
FROM LATEST_YEAR AS LY
INNER JOIN D_10_YEAR_AGO AS D10Y
ON LY.country_name = D10Y.country_name
ORDER BY 4 DESC;


--==============================================================================================================================================================
--->>> ADVANCE ANALYSIS

--(1) How has the cumulative economic output of each BRICS country evolved over time,
--and which nation has contributed the most GDP throughout the analysis period?
--RUNNING TOTAL of GDP (cumulative sum per country)
--helps:
      -- Helps analyze long-term economic growth trends, compare
      -- cumulative economic performance across BRICS nations, and
      -- understand which countries have contributed the most to
      -- overall economic output over the years.
SELECT 
     [country_name],
     [year],
     ROUND([gdp_usd] / 1e12, 2) AS GDP_USD_TRILLION,
	 ROUND(
	      SUM(gdp_usd) OVER(
		     PARTITION BY country_name 
	         ORDER BY year
			 ) / 1e12, 
			     2)  AS cumulative_gdp_trillion
FROM brics_world_bank
WHERE gdp_growth_pct != 0
ORDER BY country_name, year;

--(2) What is the 3-year average GDP growth trend for each BRICS country, 
--and which economies demonstrate the most stable long-term growth?

-- 3-year moving average helps:
        --Remove short-term fluctuations
        --Identify long-term economic trends
        --Compare economic stability across countries
        --Reduce the impact of unusual events (such as COVID-19)
SELECT
    country_name,
    year,
    ROUND(gdp_growth_pct, 2) AS gdp_growth,
    ROUND(
        AVG(gdp_growth_pct) OVER (
            PARTITION BY country_name
            ORDER BY year
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW       ---Looks at: Current year, Previous 1 year, Previous 2 years
        ),
        2
    ) AS moving_avg_3yr_growth
FROM dbo.brics_world_bank
WHERE gdp_growth_pct != 0
ORDER BY country_name, year;


---(3) Which BRICS country achieved the highest GDP growth since 2000, 
--and how does its economic expansion compare with other member nations?

-- FIRST_VALUE() retrieves the first GDP value for each country,
-- allowing all future years to be compared against the same
-- baseline (Year 2000).

-- Helps:
    --identify which BRICS economies have expanded the most
    -- over the last two decades, measure long-term economic growth,
    -- and evaluate the pace of development across countries.

SELECT
      [country_name],
      [year],
	  ROUND([gdp_usd] / 1e12, 2) AS GDP_USD_TRILLION,
	  ROUND(FIRST_VALUE(gdp_usd) OVER ( 
	                            PARTITION BY country_name
								ORDER BY year) 
								/ 1E12 ,
								   2) AS FIRST_VALUE_GDP_2000_TRILL,
	  ROUND((gdp_usd / FIRST_VALUE(gdp_usd) OVER (
	                                       PARTITION BY  country_name 
	                                       ORDER BY year) - 1)*100,              ----- Subtract 1 to convert the GDP ratio into a growth rate.
											      2) AS pct_growth_since_2000
FROM [dbo].[brics_world_bank]
WHERE gdp_usd > 0
ORDER BY country_name, year;

---======================================================================================================================================================



-- ==========================================================================================
--------------------------------COMPLETE COUNTRY SCORECARD-----------------------------------
-- One row per country. 
--Latest year. 
--All key indicators.


SELECT
    b.country_name,
    b.year,
    ROUND(b.gdp_usd          / 1e12, 2) AS gdp_trillion_usd,
    ROUND(b.gdp_per_capita,          0) AS gdp_per_person_usd,
    ROUND(b.gdp_growth_pct,          2) AS gdp_growth_pct,
    ROUND(b.population       / 1e9,  2) AS population_billion,
    ROUND(b.life_expectancy,         1) AS life_expectancy,
    ROUND(b.inflation_pct,           2) AS inflation_pct,
    ROUND(b.unemployment_pct,        2) AS unemployment_pct,
    ROUND(b.exports_usd      / 1e9,  1) AS exports_billion,
    ROUND(b.imports_usd      / 1e9,  1) AS imports_billion,
    ROUND(b.trade_pct_gdp,           1) AS trade_pct_gdp,
    ROUND(b.fdi_inflows_usd  / 1e9,  2) AS fdi_billion,
    ROUND(b.debt_pct_gdp,            1) AS debt_pct_gdp,
    ROUND(b.internet_users_pct,      1) AS internet_users_pct,
    ROUND(b.co2_per_capita,          2) AS co2_per_person,
    ROUND(b.health_expenditure_pct_gdp, 2) AS health_spend_pct_gdp

FROM dbo.brics_world_bank b
INNER JOIN (
			SELECT country_name, MAX(year) AS max_year
			FROM dbo.brics_world_bank
			WHERE gdp_usd > 0
			GROUP BY country_name
         ) latest
    ON  
	   b.country_name = latest.country_name
    AND 
	   b.year = latest.max_year
ORDER BY 
       b.gdp_usd DESC;
















