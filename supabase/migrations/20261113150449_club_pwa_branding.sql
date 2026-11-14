-- Public install metadata is a projection. Club rows, membership and join codes
-- remain behind the existing policies.
alter table public.clubs add column install_slug text;
update public.clubs
set install_slug = case id
  when '74796e65-6272-4964-8765-686172726965'::uuid then 'tyne-bridge-harriers'
  else 'club-' || id::text
end;
alter table public.clubs
  alter column install_slug set not null,
  add constraint clubs_install_slug_key unique (install_slug),
  add constraint clubs_install_slug_format
    check (install_slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and length(install_slug) <= 80);

create function runtrack_private.set_club_install_slug() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    new.install_slug := coalesce(new.install_slug, 'club-' || new.id::text);
  elsif new.install_slug is distinct from old.install_slug then
    raise exception 'A club installation URL cannot be changed';
  end if;
  return new;
end;
$$;
revoke all on function runtrack_private.set_club_install_slug() from public, anon, authenticated;
create trigger clubs_install_slug before insert or update of install_slug on public.clubs
for each row execute function runtrack_private.set_club_install_slug();

create table runtrack_private.club_logos (
  club_id uuid primary key references public.clubs(id) on delete cascade,
  png bytea not null check (
    octet_length(png) between 45 and 524288
    and substring(png from 1 for 16) = decode('89504e470d0a1a0a0000000d49484452', 'hex')
    and get_byte(png, 16) = 0 and get_byte(png, 17) = 0
    and get_byte(png, 20) = 0 and get_byte(png, 21) = 0
    and get_byte(png, 18) * 256 + get_byte(png, 19) between 1 and 512
    and get_byte(png, 22) * 256 + get_byte(png, 23) between 1 and 512
  )
);
alter table runtrack_private.club_logos enable row level security;
revoke all on table runtrack_private.club_logos from public, anon, authenticated;

-- Preserve the configured TBH theme. Seed the same palette on new environments.
update public.clubs
set theme_json = '{"colors":{"primary":"#FFFFFF","secondary":"#E0E0E0","background":"#000000"}}'
where id = '74796e65-6272-4964-8765-686172726965' and theme_json = '{}'::jsonb;

insert into runtrack_private.club_logos(club_id, png)
values ('74796e65-6272-4964-8765-686172726965', decode('
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
', 'base64'));

create function public.club_install_branding(p_slug text, p_include_logo boolean default false)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'slug', c.install_slug,
    'name', c.name,
    'primary', c.theme_json #>> '{colors,primary}',
    'background', c.theme_json #>> '{colors,background}',
    'revision', md5(extract(epoch from c.updated_at)::text),
    'logo', case when p_include_logo then (
      select encode(l.png, 'base64') from runtrack_private.club_logos l where l.club_id = c.id
    ) end
  )
  from public.clubs c
  where c.install_slug = p_slug and c.status = 'active';
$$;
revoke all on function public.club_install_branding(text, boolean) from public;
grant execute on function public.club_install_branding(text, boolean) to anon, authenticated;

create function public.update_club_branding(
  p_club_id uuid, p_name text, p_primary text, p_secondary text, p_background text,
  p_logo text default null, p_remove_logo boolean default false
) returns void language plpgsql security definer set search_path = '' as $$
begin
  -- Membership changes lock this same club row before changing roles.
  perform 1 from public.clubs where id = p_club_id and status = 'active' for update;
  if not found or not runtrack_private.is_admin(p_club_id) then
    raise exception 'Club administrator required' using errcode = '42501';
  end if;
  if p_name is null or length(btrim(p_name)) not between 1 and 120
    or p_primary is null or p_primary !~ '^#[0-9A-Fa-f]{6}$'
    or p_secondary is null or p_secondary !~ '^#[0-9A-Fa-f]{6}$'
    or p_background is null or p_background !~ '^#[0-9A-Fa-f]{6}$'
    or p_remove_logo is null
    or (p_remove_logo and p_logo is not null)
    or (p_logo is not null and length(p_logo) > 699052)
  then
    raise exception 'Enter a club name, valid hex colours and a PNG up to 512 KB';
  end if;
  if p_remove_logo then
    delete from runtrack_private.club_logos where club_id = p_club_id;
  elsif p_logo is not null then
    insert into runtrack_private.club_logos(club_id, png)
    values (p_club_id, decode(p_logo, 'base64'))
    on conflict (club_id) do update set png = excluded.png;
  end if;
  update public.clubs
  set name = btrim(p_name),
      theme_json = theme_json || jsonb_build_object(
        'colors',
        (case when jsonb_typeof(theme_json->'colors') = 'object'
          then theme_json->'colors' else '{}'::jsonb end)
        || jsonb_build_object(
          'primary', upper(p_primary), 'secondary', upper(p_secondary), 'background', upper(p_background)
        )
      )
  where id = p_club_id;
end;
$$;
revoke all on function public.update_club_branding(uuid, text, text, text, text, text, boolean) from public, anon;
grant execute on function public.update_club_branding(uuid, text, text, text, text, text, boolean) to authenticated;
