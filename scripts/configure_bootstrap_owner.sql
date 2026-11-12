-- Execute privately with an administrative psql connection to the NEW dedicated project.
-- psql quotes the input as a string value; this does not interpolate executable SQL.
\prompt 'Founding administrator email (BOOTSTRAP_OWNER_EMAIL): ' bootstrap_owner_email
select public.configure_bootstrap_owner(:'bootstrap_owner_email');
\unset bootstrap_owner_email
select public.bootstrap_status();
