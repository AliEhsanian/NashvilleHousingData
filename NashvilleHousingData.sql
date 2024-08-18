/*
 -------------------------
| Cleaning Data using SQL |
 -------------------------

Some Notes:

1. Download the data from Kaggle or GitHub. A *.csv file is universally accepted 
by all DBMS. If we have an *.xlsx file, we can convert it to a *.csv file with 
this Python code:

    import pandas as pd
    # Read the Excel file
    df = pd.read_excel('NashvilleHousingData.xlsx', sheet_name='Sheet1')
    # Write to CSV
    df.to_csv('NashvilleHousingData.csv', index=False)

2. If we import the file to the DBMS and let it create the schema, it is possible 
that the DBMS sets some column types incorrectly, for example, STRING instead of 
INTEGER or NUMERIC. We can change the column type with this query:

    ALTER TABLE NashvilleHousingData
    ALTER COLUMN UniqueID TYPE INTEGER USING employee_id::INTEGER;

However, in some DBMS (especially cloud-based services like BigQuery), we can't 
directly alter the column type, and we may need to create a new table and drop 
the old table.

Alternatively, we can use CAST() or CONVERT() whenever necessary and avoid changing 
the original table.

Another option is to define the column names and types explicitly before importing 
the data from a file.

3. Additionally, if we import the file to the DBMS and let it create the schema, 
it may set some weird names. For example, instead of "UniqueID" it may recognize 
it as "UniqueID " (with a trailing space). We can change the column name with 
this query:

    ALTER TABLE NashvilleHousingData
    RENAME COLUMN "UniqueID " TO "UniqueID";

Again, in some DBMS (especially cloud-based services like BigQuery), we can't 
directly alter the column name, and we may need to create a new table and drop 
the old table.
*/
-- --------------------------------------------------------------------------------------------------

SELECT *
FROM NashvilleHousing
LIMIT 50;

-- --------------------------------------------------------------------------------------------------
/*
 ---------------------
| Duplicate UniqueIDs |
 ---------------------
*/

-- There are some duplicates in the UniqueID column, which shound not be as it is supposed to be unique!

SELECT COUNT(*)
FROM NashvilleHousing;

SELECT COUNT(DISTINCT UniqueID)
FROM NashvilleHousing;

-- With below query, we can see the rows with duplicate UniqueIDs

WITH DuplicateUniqueIDs AS (
  SELECT UniqueID
  FROM NashvilleHousing
  GROUP BY UniqueID
  HAVING COUNT(*) > 1
)
SELECT *
FROM NashvilleHousing
WHERE UniqueID IN (SELECT UniqueID FROM DuplicateUniqueIDs);

-- As the duplicate rows seem to be wrong entries, we can delete them with this query

DELETE FROM NashvilleHousing
  WHERE UniqueID IN 
    (SELECT UniqueID FROM NashvilleHousing GROUP BY UniqueID HAVING COUNT(*) > 1);

-- --------------------------------------------------------------------------------------------------
/*
 -----------------------------
| Standardize SaleDate Format | 
 -----------------------------
*/

SELECT SaleDate, DATE(SaleDate)
FROM NashvilleHousing
LIMIT 50;

UPDATE NashvilleHousing
SET SaleDate = DATE(SaleDate);

/*
The above query may not work, either fails or doesn't change the table (depends on the DBMS).
The reason is that some rows contain data that cannot be converted to the DATE type! 
We might wonder why the SELECT command worked without raising an error. The reason 
is that SQL systems are generally soft in the SELECT command. The SELECT command attempts 
to convert the SaleDate values into the DATE type, and if the conversion fails for a 
particular row, typically won't raise an error. Instead, it returns NULL or some other 
default value for that row in the result set.
*/

/*
With the query below, we can check if all rows in the SaleDate column are convertible 
to the DATE type. If the result is empty, the UPDATE command should have worked. If 
the query returns some rows, it indicates that those rows are not easily convertible!
*/

SELECT SaleDate 
FROM NashvilleHousing 
WHERE 
  SaleDate IS NOT NULL 
  AND TRY_CAST(SaleDate AS DATE) IS NULL; -- or SAFE_CASR() is some SQL systems

-- We can delete those rows or convert the rows with another query, or set them to NULL.

UPDATE NashvilleHousing
SET SaleDate = 
  CASE 
    WHEN TRY_CAST(SaleDate AS DATE) IS NOT NULL THEN DATE(SaleDate)
    ELSE NULL
  END;

-- --------------------------------------------------------------------------------------------------
/*
 ---------------------------
| Populate Property Address |
 ---------------------------
*/

-- There are some Properties that don't have an address!!!

SELECT *
FROM NashvilleHousing 
WHERE PropertyAddress IS NULL;

/*
After exploring the data, we see there are houses that have the same ParcelID and 
Addresss. We can use this insight to populate the null addresses. This query, returns 
the houses without address and the houses with address which have the same ParcelID.
*/

SELECT 
  t1.ParcelID, t1.PropertyAddress,
  t2.ParcelID, t2.PropertyAddress
FROM NashvilleHousing t1
JOIN NashvilleHousing t2
  ON t1.ParcelID = t2.ParcelID 
     AND t1.UniqueID != t2.UniqueID
WHERE t1.PropertyAddress IS NULL;

-- If the number of rows in the above two queris is not equal, It's becuase of repeated 
-- ParcelIDs. If the output of this query is empty, it shows that the Distinct ParcelIDs are the same.

SELECT DISTINCT ParcelID
FROM NashvilleHousing 
WHERE PropertyAddress IS NULL

EXCEPT DISTINCT

SELECT DISTINCT ParcelID
FROM (
  SELECT t1.ParcelID As ParcelID
  FROM NashvilleHousing t1
  JOIN NashvilleHousing t2
  ON t1.ParcelID = t2.ParcelID 
     AND t1.UniqueID != t2.UniqueID
  WHERE t1.PropertyAddress IS NULL
) AS subquery;

-- We can populte the null addresses with this quey

UPDATE NashvilleHousing t1
SET PropertyAddress = COALESCE(t1.PropertyAddress, t2.PropertyAddress)
  FROM NashvilleHousing t1
  JOIN NashvilleHousing t2
    ON t1.ParcelID = t2.ParcelID 
       AND t1.UniqueID != t2.UniqueID
  WHERE t1.PropertyAddress IS NULL;

-- If the above query doesn't work, one of the below queries should work depending on the DBMS.

/*
UPDATE NashvilleHousing t1
SET PropertyAddress = COALESCE(t1.PropertyAddress, t2.PropertyAddress)
  FROM NashvilleHousing t2
  WHERE t1.ParcelID = t2.ParcelID
        AND t1.UniqueID != t2.UniqueID
        AND t1.PropertyAddress IS NULL;


UPDATE NashvilleHousing t1
SET PropertyAddress = 
(
  SELECT COALESCE(t1.PropertyAddress, t2.PropertyAddress)
  FROM fantasy.NashvilleHousing t1
  JOIN fantasy.NashvilleHousing t2
    ON t1.ParcelID = t2.ParcelID
       AND t1.UniqueID != t2.UniqueID
  LIMIT 1
)
WHERE t1.PropertyAddress IS NULL;


UPDATE NashvilleHousing t1
SET PropertyAddress = 
(
  SELECT COALESCE(t1.PropertyAddress, t2.PropertyAddress)
  FROM fantasy.NashvilleHousing t2
  WHERE t1.ParcelID = t2.ParcelID
        AND t1.UniqueID != t2.UniqueID
  LIMIT 1
)
WHERE t1.PropertyAddress IS NULL;


UPDATE NashvilleHousing t1
SET t1.PropertyAddress = t2.PropertyAddress
FROM (
  SELECT 
    ParcelID,
    PropertyAddress,
    ROW_NUMBER() OVER (PARTITION BY ParcelID ORDER BY ParcelID) AS rn
  FROM NashvilleHousing
  WHERE PropertyAddress IS NOT NULL
) t2
WHERE t1.ParcelID = t2.ParcelID
      AND t2.rn = 1
      AND t1.PropertyAddress IS NULL;
*/

-- --------------------------------------------------------------------------------------------------
/*
 -----------------------------------------------
| Extracting Address, City from PropertyAddress |
| and Address, City, State from OwnerAddress    |
 -----------------------------------------------
*/

SELECT PropertyAddress
FROM NashvilleHousing
LIMIT 50;

/*
In most rows, the address, city, and state in the PropertyAddress and OwnerAddress columns
are separated by a comma (','), but not in all of them or some rows may not include the city or state.
Some string functions won't raise an error in these situations and will return an empty string (''),
but others might raise an error. If an error is raised, use TRY or SAFE functions.
*/

SELECT 
  -- Split PropertyAddress
  SPLIT_PART(PropertyAddress, ',', 1) AS Property_Address,
  SPLIT_PART(PropertyAddress, ',', 2) AS Property_City,
  
  -- Split OwnerAddress
  SPLIT_PART(OwnerAddress, ',', 1) AS Owner_Address,
  SPLIT_PART(OwnerAddress, ',', 2) AS Owner_City,
  SPLIT_PART(OwnerAddress, ',', 3) AS Owner_State
FROM NashvilleHousing;

-- There are lots of functions that can be used for this task depends on the DBMS.
/*
  (STRING_TO_ARRAY(PropertyAddress, ','))[1] AS Property_Address

  SUBSTRING(PropertyAddress, 1, CHARINDEX(',', PropertyAddress) -1 ) AS Property_Address

  PARSENAME(REPLACE(PropertyAddress, ',', '.') , 2) AS Property_Address

  SPLIT(PropertyAddress, ',')[SAFE_OFFSET(0)] AS Property_Address
*/  

-- We can add the new columns to the table with the below queries.

ALTER TABLE NashvilleHousing
  ADD COLUMN Property_Address TEXT, -- NVARCHAR(255), STRING,... depends on the DBMS
  ADD COLUMN Property_City TEXT,
  ADD COLUMN Owner_Address TEXT,
  ADD COLUMN Owner_City TEXT,
  ADD COLUMN Owner_State TEXT;

UPDATE NashvilleHousing
SET 
  Property_Address = SPLIT_PART(PropertyAddress, ',', 1), -- The function can change, depends on the DBMS
  Property_City = SPLIT_PART(PropertyAddress, ',', 2),
  Owner_Address = SPLIT_PART(OwnerAddress, ',', 1),
  Owner_City = SPLIT_PART(OwnerAddress, ',', 2),
  Owner_State = SPLIT_PART(OwnerAddress, ',', 3);

-- --------------------------------------------------------------------------------------------------
/*
 ---------------------------------------------
| Change Y to Yes and N to No in SoldAsVacant |
 ---------------------------------------------
*/

SELECT DISTINCT(SoldAsVacant), COUNT(SoldAsVacant) AS countNY
FROM NashvilleHousing
GROUP BY SoldAsVacant
ORDER BY countNY;

-- Because the number of 'N' and 'Y's are significantly lower, we change them to 'No' and 'Yes'.

SELECT SoldAsVacant, 
  CASE 
    WHEN SoldAsVacant = 'N' THEN 'No'
	  WHEN SoldAsVacant = 'Y' THEN 'Yes'
	  ELSE SoldAsVacant
  END
FROM NashvilleHousing;

-- We can change the table with this query

UPDATE NashvilleHousing
SET SoldAsVacant = 
  CASE 
    WHEN SoldAsVacant = 'N' THEN 'No'
    WHEN SoldAsVacant = 'Y' THEN 'Yes'
    ELSE SoldAsVacant
  END;
-- WHERE SoldAsVacant IS NOT NULL; -- Some DBMS like BigQuery need a WHERE cluase in the UPDATE command 

-- --------------------------------------------------------------------------------------------------
/*
 ---------------------
| Find Duplicate Rows |
 ---------------------
*/

SELECT COUNT(*)
FROM NashvilleHousing;

-- We can see that there are duplicates in these columns. These columns are selected because 
-- there is a high chance to determine unique transactions based on them. Also, there is no NULL
-- in these columns.

SELECT COUNT(DISTINCT ParcelID)
FROM NashvilleHousing;

SELECT COUNT(DISTINCT PropertyAddress)
FROM NashvilleHousing;

SELECT COUNT(DISTINCT SaleDate, SalePrice)
FROM NashvilleHousing;

-- If the above query doesn't work, the below query should work
/*
SELECT COUNT(*)
FROM (
    SELECT DISTINCT SaleDate, SalePrice
    FROM NashvilleHousing
);
*/

SELECT COUNT(DISTINCT LegalReference)
FROM fantasy.NashvilleHousing;

-- We can find the duplicate rows with this query

WITH DupRows AS (
  Select 
    *,
    ROW_NUMBER() OVER(
      PARTITION BY 
        ParcelID,
			  PropertyAddress,
			  SalePrice,
			  SaleDate,
			  LegalReference
			ORDER BY UniqueID
		) AS rn
FROM NashvilleHousing
)

SELECT COUNT(*) -- SELECT * shows the duplicate rows
FROM DupRows
WHERE rn > 1;

-- We can find the duplicateb rows using this query too. But this is not useful for more actions.
/*
SELECT 
  ParcelID, 
  PropertyAddress, 
  SalePrice, 
  SaleDate, 
  LegalReference,
  COUNT(*) as DuplicateCount
FROM NashvilleHousing
GROUP BY 
  ParcelID, 
  PropertyAddress, 
  SalePrice, 
  SaleDate, 
  LegalReference
HAVING  COUNT(*) > 1
ORDER BY DuplicateCount DESC;
*/

-- We can delete the duplicate rows from the table with below query but
-- it's recommended not to do this.
/*
WITH DupRows AS (
  Select 
    *,
    ROW_NUMBER() OVER(
      PARTITION BY 
        ParcelID,
			  PropertyAddress,
			  SalePrice,
			  SaleDate,
			  LegalReference
			ORDER BY UniqueID
		) AS rn
FROM NashvilleHousing
)

DELETE FROM NashvilleHousing
  WHERE UniqueID IN (
    SELECT UniqueID
    FROM DupRows
    WHERE rn > 1
  );
*/

-- If we don't want the duplicate rows, temporary table or view or materialized view
-- is the usual solution. We can create a temporary table with below query

CREATE TEMPORARY TABLE temp_NashvilleHousing AS

  WITH DupRows AS (
    Select 
      *,
      ROW_NUMBER() OVER(
        PARTITION BY 
          ParcelID,
			    PropertyAddress,
			    SalePrice,
			    SaleDate,
			    LegalReference
			  ORDER BY UniqueID
		  ) AS rn
    FROM NashvilleHousing
  )

  SELECT *
  FROM DupRows
  WHERE rn = 1;

-- --------------------------------------------------------------------------------------------------



