-- Always acquire the athlete lock before a connection row lock. Withdrawal uses
-- the same order, so reconciliation/token refresh cannot deadlock with disconnect.
create or replace function public.reconcile_health_deletions(p_connection_id uuid,p_seen_before timestamptz)
returns integer language plpgsql security definer set search_path='' as $$
declare v_user uuid; v_connection public.health_connections; v_deleted integer;
begin
 select user_id into v_user from public.health_connections where id=p_connection_id;
 if not found then raise exception 'Health connection is not active' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(v_user::text,1));
 select * into v_connection from public.health_connections where id=p_connection_id and user_id=v_user and status in ('connected','error') for update;
 if not found then raise exception 'Health connection is not active' using errcode='42501'; end if;
 if v_connection.provider='google_health' and not public.health_consent_active(v_user) then raise exception 'Explicit health consent required' using errcode='42501'; end if;
 if p_seen_before is null or p_seen_before>now()+interval '1 minute' then raise exception 'Invalid provider reconciliation time'; end if;
 delete from public.activities where user_id=v_user and provider=v_connection.provider and provider_seen_at<p_seen_before;
 get diagnostics v_deleted=row_count;
 return v_deleted;
end $$;

create or replace function public.health_credentials_store(p_connection_id uuid,p_access_token_ciphertext text,p_refresh_token_ciphertext text,p_expires_at timestamptz,p_scopes text[])
returns void language plpgsql security definer set search_path='' as $$
declare v_user uuid; v_provider text;
begin
 select user_id into v_user from public.health_connections where id=p_connection_id;
 if not found then raise exception 'Health connection is not active' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(v_user::text,1));
 select provider into v_provider from public.health_connections where id=p_connection_id and user_id=v_user and status in ('connected','error') for update;
 if not found then raise exception 'Health connection is not active' using errcode='42501'; end if;
 if v_provider='google_health' and not public.health_consent_active(v_user) then raise exception 'Explicit health consent required' using errcode='42501'; end if;
 insert into runtrack_private.health_credentials(connection_id,access_token_ciphertext,refresh_token_ciphertext,expires_at,scopes)
 values(p_connection_id,p_access_token_ciphertext,p_refresh_token_ciphertext,p_expires_at,p_scopes)
 on conflict(connection_id) do update set access_token_ciphertext=excluded.access_token_ciphertext,refresh_token_ciphertext=excluded.refresh_token_ciphertext,expires_at=excluded.expires_at,scopes=excluded.scopes,updated_at=now();
end $$;

-- A callback is bound to the exact explicit grant and one-time OAuth state.
-- A later grant must never make an old callback valid again.
create function public.prepare_health_oauth_connection(p_user_id uuid,p_consent_id bigint,p_state_hash text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_connection public.health_connections;
begin
 perform pg_advisory_xact_lock(hashtextextended(p_user_id::text,1));
 if p_consent_id is null or not public.health_consent_active(p_user_id,p_consent_id) then raise exception 'Current explicit health consent required' using errcode='42501'; end if;
 if not exists(select 1 from public.oauth_states where state_hash=p_state_hash and user_id=p_user_id and health_consent_id=p_consent_id and consumed_at is not null and expires_at>now()) then
  raise exception 'Health connection request is no longer active' using errcode='42501';
 end if;
 insert into public.health_connections(user_id,provider,status) values(p_user_id,'google_health','error')
 on conflict(user_id,provider) do update set status='error',last_error=null
 returning * into v_connection;
 return to_jsonb(v_connection);
end $$;

create function public.complete_health_oauth_connection(p_connection_id uuid,p_consent_id bigint,p_state_hash text,p_provider_user_id text,p_access_token_ciphertext text,p_refresh_token_ciphertext text,p_expires_at timestamptz,p_scopes text[])
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_user uuid; v_connection public.health_connections;
begin
 select user_id into v_user from public.health_connections where id=p_connection_id and provider='google_health';
 if not found then raise exception 'Health connection is not active' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(v_user::text,1));
 if p_consent_id is null or not public.health_consent_active(v_user,p_consent_id) then raise exception 'Current explicit health consent required' using errcode='42501'; end if;
 if not exists(select 1 from public.oauth_states where state_hash=p_state_hash and user_id=v_user and health_consent_id=p_consent_id and consumed_at is not null and expires_at>now()) then
  raise exception 'Health connection request is no longer active' using errcode='42501';
 end if;
 if p_provider_user_id is null or length(p_provider_user_id) not between 1 and 1024 then raise exception 'Invalid provider identity' using errcode='22023'; end if;
 perform public.health_credentials_store(p_connection_id,p_access_token_ciphertext,p_refresh_token_ciphertext,p_expires_at,p_scopes);
 update public.health_connections set provider_user_id=p_provider_user_id,sync_cursor='{}'::jsonb,status='connected',last_error=null
 where id=p_connection_id returning * into v_connection;
 return to_jsonb(v_connection);
end $$;

revoke all on function public.reconcile_health_deletions(uuid,timestamptz),public.health_credentials_store(uuid,text,text,timestamptz,text[]),public.prepare_health_oauth_connection(uuid,bigint,text),public.complete_health_oauth_connection(uuid,bigint,text,text,text,text,timestamptz,text[]) from public,anon,authenticated;
grant execute on function public.reconcile_health_deletions(uuid,timestamptz),public.health_credentials_store(uuid,text,text,timestamptz,text[]),public.prepare_health_oauth_connection(uuid,bigint,text),public.complete_health_oauth_connection(uuid,bigint,text,text,text,text,timestamptz,text[]) to service_role;
