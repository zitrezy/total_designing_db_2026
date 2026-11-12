DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'inspector') THEN
        CREATE ROLE inspector LOGIN PASSWORD 'NetoSQL2025';
    ELSE
        ALTER ROLE inspector LOGIN PASSWORD 'NetoSQL2025';
    END IF;
END $$;

ALTER ROLE inspector SET search_path TO shiryaev_food, exts, public;

GRANT ALL PRIVILEGES ON SCHEMA shiryaev_food TO inspector;
GRANT ALL PRIVILEGES ON ALL TABLES     IN SCHEMA shiryaev_food TO inspector;
GRANT ALL PRIVILEGES ON ALL SEQUENCES  IN SCHEMA shiryaev_food TO inspector;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS  IN SCHEMA shiryaev_food TO inspector;
GRANT ALL PRIVILEGES ON ALL PROCEDURES IN SCHEMA shiryaev_food TO inspector;

GRANT USAGE ON SCHEMA exts TO inspector;              -- для exts.uuid_generate_v4()
GRANT USAGE ON SCHEMA information_schema TO inspector;
GRANT USAGE ON SCHEMA pg_catalog TO inspector;
