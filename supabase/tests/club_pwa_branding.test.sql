begin;

insert into auth.users(id, email, email_confirmed_at) values
  ('db810000-0000-4000-8000-000000000001', 'branding-admin@example.test', now()),
  ('db810000-0000-4000-8000-000000000002', 'branding-athlete@example.test', now());
insert into public.profiles(id) values
  ('db810000-0000-4000-8000-000000000001'),
  ('db810000-0000-4000-8000-000000000002');
insert into public.clubs(id, name, install_slug) values
  ('db810000-0000-4000-8000-000000000011', 'Branding fixture', 'branding-fixture');
insert into public.clubs(id, name) values
  ('db810000-0000-4000-8000-000000000012', 'Private fixture');
insert into public.club_memberships(club_id, user_id, role) values
  ('db810000-0000-4000-8000-000000000011', 'db810000-0000-4000-8000-000000000001', 'admin'),
  ('db810000-0000-4000-8000-000000000011', 'db810000-0000-4000-8000-000000000002', 'athlete'),
  ('db810000-0000-4000-8000-000000000012', 'db810000-0000-4000-8000-000000000002', 'admin');

set local role anon;
do $$
declare metadata jsonb := public.club_install_branding('tyne-bridge-harriers');
begin
  assert metadata->>'name' = 'Tyne Bridge Harriers';
  assert metadata->>'logo' is null;
  assert not (metadata ? 'club_id' or metadata ? 'memberships' or metadata ? 'theme_json');
  assert public.club_install_branding('tyne-bridge-harriers', true)->>'logo' is not null;
  assert public.club_install_branding('missing-club') is null;
  assert not has_table_privilege('public.clubs', 'SELECT');
  assert not has_function_privilege('public.update_club_branding(uuid,text,text,text,text,text,boolean)', 'EXECUTE');
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'db810000-0000-4000-8000-000000000002', true);
do $$
begin
  begin
    perform public.update_club_branding(
      'db810000-0000-4000-8000-000000000011', 'Forged', '#112233', '#334455', '#FFFFFF');
    raise exception 'Athlete wrote branding using admin membership in another club';
  exception when insufficient_privilege then null;
  end;
  assert not has_column_privilege('public.clubs', 'install_slug', 'UPDATE');
  assert not has_table_privilege('runtrack_private.club_logos', 'SELECT');
end $$;

select set_config('request.jwt.claim.sub', 'db810000-0000-4000-8000-000000000001', true);
do $$
declare
  club_id constant uuid := 'db810000-0000-4000-8000-000000000011';
  seed_logo text := public.club_install_branding('tyne-bridge-harriers', true)->>'logo';
begin
  perform public.update_club_branding(club_id, 'New club name', '#123abc', '#112233', '#FFFFFF', seed_logo);
  assert public.club_install_branding('branding-fixture')->>'name' = 'New club name';
  assert public.club_install_branding('branding-fixture')->>'primary' = '#123ABC';
  assert public.club_install_branding('branding-fixture', true)->>'logo' = seed_logo;
  begin
    perform public.update_club_branding(club_id, 'Bad colour', 'red', '#112233', '#FFFFFF');
    raise exception 'Invalid colour accepted' using errcode = 'XX000';
  exception when raise_exception then null;
  end;
  begin
    perform public.update_club_branding(club_id, 'Bad logo', '#123ABC', '#112233', '#FFFFFF', 'aGVsbG8=');
    raise exception 'Invalid PNG accepted';
  exception when check_violation then null;
  end;
  assert public.club_install_branding('branding-fixture')->>'name' = 'New club name';
  perform public.update_club_branding(club_id, 'New club name', '#123ABC', '#112233', '#FFFFFF', null, true);
  assert public.club_install_branding('branding-fixture', true)->>'logo' is null;
end $$;

reset role;
update public.clubs set status = 'inactive' where install_slug = 'branding-fixture';
do $$
begin
  assert public.club_install_branding('branding-fixture') is null;
  assert (select install_slug from public.clubs where id = 'db810000-0000-4000-8000-000000000012')
    = 'club-db810000-0000-4000-8000-000000000012';
end $$;

rollback;
