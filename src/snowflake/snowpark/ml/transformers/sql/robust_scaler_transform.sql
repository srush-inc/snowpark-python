create database if not exists feature_engineering;
create schema if not exists feature_engineering.robust_scaler;
use database feature_engineering;
use schema feature_engineering.robust_scaler;
use schema feature_engineering.robust_scaler_clone;
create stage if not exists stage_test;

create or replace function feature_engineering.robust_scaler.transform(value float)
returns float
language python
runtime_version = 3.8
packages = ('pandas')
imports=('@stage_test/temp_robust_scaler.csv')
handler='transform'
as
$$
import sys
import pandas as pd
import numpy as np
import csv
from _snowflake import vectorized

IMPORT_DIRECTORY_NAME = "snowflake_import_directory"
import_dir = sys._xoptions[IMPORT_DIRECTORY_NAME]
FILENAME = "temp_robust_scaler.csv"

def _handle_zeros_in_scale(scale, copy=True, constant_mask=None):
    """Set scales of near constant features to 1.
    The goal is to avoid division by very small or zero values.
    Near constant features are detected automatically by identifying
    scales close to machine precision unless they are precomputed by
    the caller and passed with the `constant_mask` kwarg.
    Typically for standard scaling, the scales are the standard
    deviation while near constant features are better detected on the
    computed variances which are closer to machine precision by
    construction.
    """
    # if we are fitting on 1D arrays, scale might be a scalar
    if np.isscalar(scale):
        if scale == 0.0:
            scale = 1.0
        return scale
    elif isinstance(scale, np.ndarray):
        if constant_mask is None:
            # Detect near constant values to avoid dividing by a very small
            # value that could lead to surprising results and numerical
            # stability issues.
            constant_mask = scale < 10 * np.finfo(scale.dtype).eps

        if copy:
            # New array to avoid side-effects
            scale = scale.copy()
        scale[constant_mask] = 1.0
        return scale

@vectorized(input=pd.DataFrame)
def transform(df):
    with open(import_dir + FILENAME, 'r') as file:
        reader = csv.reader(file)
        row = next(reader)
        center, quantile_min, quantile_max = float(row[0]), float(row[1]), float(row[2])

    scale = quantile_max - quantile_min
    scale = _handle_zeros_in_scale(scale, copy=False)
    return df[0].sub(center).div(scale)
$$;

show functions like '%transform%' in robust_scaler;

-- clone transform() to the transformer_clone schema
create or replace schema robust_scaler_clone clone feature_engineering.robust_scaler;

show procedures like '%fit%' in robust_scaler_clone;
show functions like '%transform%' in robust_scaler_clone;
desc function transform(varchar);
list @stage_test;


// ======================
//         TEST
// ======================

create or replace table table_test_transform as select uniform(1, 1000, random(1)) as integer from table(generator(rowcount => 1000000));
select integer, transform(integer) from table_test_transform;