# Local PostgreSQL development

The local database is PostgreSQL 16. Its data is retained in the named Docker
volume `securescan-postgres-development-data`, so stopping or recreating the
container does not remove development data. The default credentials in Compose
are development-only and must not be reused in a deployed environment.

## Start and migrate

Run these commands from the repository root:

```sh
docker compose -f deployment/compose.yaml up -d --wait
./database/scripts/migrate.sh up
./database/scripts/seed.sh
./database/scripts/verify.sh
```

`migrate.sh up` creates `schema_migrations`, applies pending `*.up.sql` files
in version order, and records each version in the same transaction as its DDL.
It takes a PostgreSQL advisory lock for each migration, making concurrent
migration attempts safe. Re-running migration and seed commands is a no-op.

The scripts use `securescan` / `securescan_dev` by default. Override Compose
and the scripts consistently by exporting `POSTGRES_USER`, `POSTGRES_DB`,
`POSTGRES_PASSWORD`, and optionally `POSTGRES_PORT` before running them.

## Roll back and reset

Roll back the latest applied version, then apply it again:

```sh
./database/scripts/migrate.sh down
./database/scripts/migrate.sh up
```

Reset all data in the local database, recreate the schema, apply every
migration, and load the development seed:

```sh
./database/scripts/reset.sh
./database/scripts/verify.sh
```

`reset.sh` is destructive: it drops the local database's `public` schema. It
does not remove the persistent Docker volume. To remove the container while
retaining data, run:

```sh
docker compose -f deployment/compose.yaml down
```

To deliberately remove the container **and all local PostgreSQL data**, run:

```sh
docker compose -f deployment/compose.yaml down --volumes
```

## Files and migration rules

- `migrations/VNNN__description.up.sql` contains forward-only SQL for a version.
- The matching `.down.sql` reverses only that version.
- `seeds/development.sql` contains deterministic local fixtures, not production
  data. It is safe to run repeatedly.
- `tests/verify.sql` checks tables, named constraints and foreign keys, planned
  indexes, migration state, and seed rows. Its rollback-only acceptance fixtures
  prove result-batch atomicity, completion retry safety, owner scoping, stable
  result/history ordering, rejection of a port-zero scan, successful and blocked
  audit trails, duplicate-event rejection, safe metadata enforcement, and
  rollback of a lifecycle update when its audit insert fails.

Do not put `BEGIN` or `COMMIT` in a migration file; the runner supplies the
transaction. Production index migrations should use a deployment runner that
supports `CREATE INDEX CONCURRENTLY`, which PostgreSQL forbids inside a
transaction. Never put role passwords or other secrets in migrations or seed
files.
