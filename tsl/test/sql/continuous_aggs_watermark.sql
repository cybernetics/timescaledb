-- This file and its contents are licensed under the Timescale License.
-- Please see the included NOTICE for copyright information and
-- LICENSE-TIMESCALE for a copy of the license.

\c :TEST_DBNAME :ROLE_SUPERUSER
-- stop the continous aggregate background workers from interfering
SELECT _timescaledb_internal.stop_background_workers();
\c :TEST_DBNAME :ROLE_DEFAULT_PERM_USER

CREATE TABLE continuous_agg_test(time int, data int);
select create_hypertable('continuous_agg_test', 'time', chunk_time_interval=> 10);


-- watermark tabels start out empty
SELECT * FROM _timescaledb_catalog.continuous_aggs_invalidation_threshold;
SELECT * from _timescaledb_catalog.continuous_aggs_hypertable_invalidation_log;

-- inserting into a table that does not have continuous_agg_insert_trigger doesn't change the watermark
INSERT INTO continuous_agg_test VALUES (10, 1), (11, 2), (21, 3), (22, 4);

SELECT * FROM _timescaledb_catalog.continuous_aggs_invalidation_threshold;
SELECT * from _timescaledb_catalog.continuous_aggs_hypertable_invalidation_log;

-- create the trigger
CREATE TRIGGER continuous_agg_insert_trigger
    AFTER INSERT ON continuous_agg_test
    FOR EACH ROW EXECUTE PROCEDURE _timescaledb_internal.continuous_agg_invalidation_trigger(1);

-- inserting into the table still doesn't change the watermark since there's no
-- continuous_aggs_invalidation_threshold. We treat that case as a invalidation_watermark of
-- BIG_INT_MIN, since the first run of the aggregation will need to scan the
-- entire table anyway.
INSERT INTO continuous_agg_test VALUES (10, 1), (11, 2), (21, 3), (22, 4);

SELECT * FROM _timescaledb_catalog.continuous_aggs_invalidation_threshold;
SELECT * from _timescaledb_catalog.continuous_aggs_hypertable_invalidation_log;

-- set the continuous_aggs_invalidation_threshold to 15, any insertions below that value need an invalidation
\c :TEST_DBNAME :ROLE_SUPERUSER
INSERT INTO _timescaledb_catalog.continuous_aggs_invalidation_threshold VALUES (1, 15);
\c :TEST_DBNAME :ROLE_DEFAULT_PERM_USER

INSERT INTO continuous_agg_test VALUES (10, 1), (11, 2), (21, 3), (22, 4);

SELECT * FROM _timescaledb_catalog.continuous_aggs_invalidation_threshold;
SELECT * from _timescaledb_catalog.continuous_aggs_hypertable_invalidation_log;

-- INSERTs only above the continuous_aggs_invalidation_threshold won't change the continuous_aggs_hypertable_invalidation_log
INSERT INTO continuous_agg_test VALUES (21, 3), (22, 4);

SELECT * FROM _timescaledb_catalog.continuous_aggs_invalidation_threshold;
SELECT * from _timescaledb_catalog.continuous_aggs_hypertable_invalidation_log;

-- INSERTs only below the continuous_aggs_invalidation_threshold will change the continuous_aggs_hypertable_invalidation_log
INSERT INTO continuous_agg_test VALUES (10, 1), (11, 2);

SELECT * FROM _timescaledb_catalog.continuous_aggs_invalidation_threshold;
SELECT * from _timescaledb_catalog.continuous_aggs_hypertable_invalidation_log;

-- test INSERTing other values
INSERT INTO continuous_agg_test VALUES (1, 7), (12, 6), (24, 5), (51, 4);

SELECT * FROM _timescaledb_catalog.continuous_aggs_invalidation_threshold;
SELECT * from _timescaledb_catalog.continuous_aggs_hypertable_invalidation_log;

-- INSERT after dropping a COLUMN
ALTER TABLE continuous_agg_test DROP COLUMN data;

INSERT INTO continuous_agg_test VALUES (-1), (-2), (-3), (-4);

SELECT * FROM _timescaledb_catalog.continuous_aggs_invalidation_threshold;
SELECT * from _timescaledb_catalog.continuous_aggs_hypertable_invalidation_log;

INSERT INTO continuous_agg_test VALUES (100);

SELECT * FROM _timescaledb_catalog.continuous_aggs_invalidation_threshold;
SELECT * from _timescaledb_catalog.continuous_aggs_hypertable_invalidation_log;

-- INSERT after adding a COLUMN
ALTER TABLE continuous_agg_test ADD COLUMN d BOOLEAN;

INSERT INTO continuous_agg_test VALUES (-6, true), (-7, false), (-3, true), (-4, false);

SELECT * FROM _timescaledb_catalog.continuous_aggs_invalidation_threshold;
SELECT * from _timescaledb_catalog.continuous_aggs_hypertable_invalidation_log;

INSERT INTO continuous_agg_test VALUES (120, false), (200, true);

SELECT * FROM _timescaledb_catalog.continuous_aggs_invalidation_threshold;
SELECT * from _timescaledb_catalog.continuous_aggs_hypertable_invalidation_log;

DROP TABLE continuous_agg_test CASCADE;
\c :TEST_DBNAME :ROLE_SUPERUSER
TRUNCATE _timescaledb_catalog.continuous_aggs_hypertable_invalidation_log;
TRUNCATE _timescaledb_catalog.continuous_aggs_invalidation_threshold;
\c :TEST_DBNAME :ROLE_DEFAULT_PERM_USER

-- CREATE VIEW creates the invalidation trigger correctly
CREATE TABLE ca_inval_test(time int);
SELECT create_hypertable('ca_inval_test', 'time', chunk_time_interval=> 10);
CREATE VIEW cit_view
    WITH ( timescaledb.continuous, timescaledb.refresh_interval='72 hours')
    AS SELECT time_bucket('5', time), COUNT(time)
        FROM ca_inval_test
        GROUP BY 1;

INSERT INTO ca_inval_test SELECT generate_series(0, 5);

SELECT * FROM _timescaledb_catalog.continuous_aggs_invalidation_threshold;
SELECT * from _timescaledb_catalog.continuous_aggs_hypertable_invalidation_log;

\c :TEST_DBNAME :ROLE_SUPERUSER
INSERT INTO _timescaledb_catalog.continuous_aggs_invalidation_threshold VALUES (2, 10);
\c :TEST_DBNAME :ROLE_DEFAULT_PERM_USER

INSERT INTO ca_inval_test SELECT generate_series(5, 10);

SELECT * FROM _timescaledb_catalog.continuous_aggs_invalidation_threshold;
SELECT * from _timescaledb_catalog.continuous_aggs_hypertable_invalidation_log;

INSERT INTO ca_inval_test SELECT generate_series(11, 20);

SELECT * FROM _timescaledb_catalog.continuous_aggs_invalidation_threshold;
SELECT * from _timescaledb_catalog.continuous_aggs_hypertable_invalidation_log;

DROP TABLE ca_inval_test CASCADE;
\c :TEST_DBNAME :ROLE_SUPERUSER
TRUNCATE _timescaledb_catalog.continuous_aggs_hypertable_invalidation_log;
TRUNCATE _timescaledb_catalog.continuous_aggs_invalidation_threshold;
\c :TEST_DBNAME :ROLE_DEFAULT_PERM_USER

-- invalidation trigger is created correctly on chunks that existed before
-- the view was created
CREATE TABLE ts_continuous_test(time INTEGER, location INTEGER);
    SELECT create_hypertable('ts_continuous_test', 'time', chunk_time_interval => 10);
INSERT INTO ts_continuous_test SELECT i, i FROM
    (SELECT generate_series(0, 29) AS i) AS i;
CREATE VIEW continuous_view
    WITH ( timescaledb.continuous, timescaledb.refresh_interval='72 hours')
    AS SELECT time_bucket('5', time), COUNT(location)
        FROM ts_continuous_test
        GROUP BY 1;

SELECT * FROM _timescaledb_catalog.continuous_aggs_invalidation_threshold;
SELECT * from _timescaledb_catalog.continuous_aggs_hypertable_invalidation_log;

\c :TEST_DBNAME :ROLE_SUPERUSER
INSERT INTO _timescaledb_catalog.continuous_aggs_invalidation_threshold VALUES (4, 2);
\c :TEST_DBNAME :ROLE_DEFAULT_PERM_USER

INSERT INTO ts_continuous_test VALUES (1, 1);

SELECT * FROM _timescaledb_catalog.continuous_aggs_invalidation_threshold;
SELECT * from _timescaledb_catalog.continuous_aggs_hypertable_invalidation_log;