begin;
create schema if not exists cat_private;
revoke all on schema cat_private from public,anon,authenticated;
grant usage on schema cat_private to service_role;
create table cat_private.users(id uuid primary key references auth.users(id) on delete cascade, role text not null default 'participant' check(role in ('participant','admin','owner')), enabled boolean not null default false, created_at timestamptz default now());
create table cat_private.questions(code text primary key, version integer not null default 1, payload jsonb not null, archived boolean default false, updated_at timestamptz default now());
create table cat_private.packages(id text primary key, title text not null, mode text not null check(mode in ('learn','exam')), duration integer not null check(duration between 60 and 14400), codes text[] not null, published boolean default false, official_format boolean default false);
create table cat_private.attempts(id uuid primary key default gen_random_uuid(), user_id uuid not null references cat_private.users(id), request_id uuid not null, package_id text not null, title text not null, mode text not null, official_format boolean not null, started_at timestamptz not null default clock_timestamp(), expires_at timestamptz not null, status text not null default 'active' check(status in ('active','submitted','expired')), snapshot jsonb not null, answers jsonb not null default '{}', revision integer not null default 0, writer uuid not null, result jsonb, unique(user_id,request_id));
create unique index cat_one_active on cat_private.attempts(user_id) where status='active';
create index cat_attempt_user on cat_private.attempts(user_id,started_at desc);
create table cat_private.receipts(attempt_id uuid references cat_private.attempts(id),request_id uuid, payload jsonb not null, primary key(attempt_id,request_id));
create table cat_private.audit(id bigint generated always as identity primary key, actor uuid, action text, detail jsonb, created_at timestamptz default now());
create table cat_private.rate_limits(actor uuid primary key, window_at timestamptz not null, hits integer not null);
alter table cat_private.users enable row level security;
alter table cat_private.questions enable row level security;
alter table cat_private.packages enable row level security;
alter table cat_private.attempts enable row level security;
alter table cat_private.receipts enable row level security;
alter table cat_private.audit enable row level security;
alter table cat_private.rate_limits enable row level security;
grant all on all tables in schema cat_private to service_role;
grant usage,select on all sequences in schema cat_private to service_role;

create function cat_private.validate_question(q jsonb) returns boolean language plpgsql immutable set search_path='' as $$
declare o jsonb; s integer; total integer:=0; best integer:=0; seen text[]:='{}';
begin
 if coalesce(q->>'category','') not in ('TWK','TIU','TKP') or coalesce(length(q->>'stem'),0) not between 10 and 6000 or coalesce(length(q->>'explanation'),0)<10 or coalesce(jsonb_typeof(q->'options'),'')<>'array' or jsonb_array_length(q->'options')<>5 then return false; end if;
 for o in select value from jsonb_array_elements(q->'options') loop
  if coalesce(length(o->>'text'),0) not between 1 and 2000 or o->>'id' not in ('A','B','C','D','E') or (o->>'id')=any(seen) then return false; end if;
  seen:=array_append(seen,o->>'id'); s:=(o->>'score')::integer;
  if s is null or (q->>'category'='TKP' and s not between 1 and 5) or (q->>'category'<>'TKP' and s not in (0,5)) then return false; end if;
  total:=total+s; if s=5 then best:=best+1; end if;
 end loop;
 if (select count(distinct trim(value->>'text')) from jsonb_array_elements(q->'options'))<>5 then return false; end if;
 return best=1 and (q->>'category'='TKP' or total=5);
exception when others then return false;
end $$;

create function cat_private.finish(aid uuid, finish_status text) returns void language plpgsql set search_path='' as $$
declare a cat_private.attempts; q jsonb; o jsonb; pts integer; twk integer:=0; tiu integer:=0; tkp integer:=0; n integer:=0; counts jsonb:='{"TWK":0,"TIU":0,"TKP":0}';
begin
 select * into a from cat_private.attempts where id=aid for update;
 if a.status<>'active' then return; end if;
 for q in select value from jsonb_array_elements(a.snapshot) loop
  pts:=0;
  if a.answers ? (q->>'code') then n:=n+1; end if;
  for o in select value from jsonb_array_elements(q->'options') loop
   if o->>'id'=a.answers->(q->>'code')->>'option' then pts:=(o->>'score')::integer; end if;
  end loop;
  counts:=jsonb_set(counts,array[q->>'category'],to_jsonb((counts->>(q->>'category'))::int+1));
  case q->>'category' when 'TWK' then twk:=twk+pts; when 'TIU' then tiu:=tiu+pts; else tkp:=tkp+pts; end case;
 end loop;
 update cat_private.attempts set status=finish_status, result=jsonb_build_object('TWK',twk,'TIU',tiu,'TKP',tkp,'total',twk+tiu+tkp,'maximum',jsonb_array_length(a.snapshot)*5,'answered',n,'count',jsonb_array_length(a.snapshot),'counts',counts,'finished_at',clock_timestamp(),'passed',case when a.official_format then twk>=65 and tiu>=80 and tkp>=166 else null end) where id=aid;
end $$;

create function cat_private.attempt_view(aid uuid) returns jsonb language plpgsql set search_path='' as $$
declare a cat_private.attempts; qs jsonb;
begin
 select * into a from cat_private.attempts where id=aid;
 select jsonb_agg(case when a.status<>'active' or (a.mode='learn' and a.answers ? (q->>'code')) then q else (q-'explanation'-'tip'-'steps') || jsonb_build_object('options',(select jsonb_agg(o-'score'-'reason') from jsonb_array_elements(q->'options') o)) end order by pos) into qs from jsonb_array_elements(a.snapshot) with ordinality x(q,pos);
 return jsonb_build_object('id',a.id,'title',a.title,'mode',a.mode,'status',a.status,'started_at',a.started_at,'expires_at',a.expires_at,'server_now',clock_timestamp(),'revision',a.revision,'questions',qs,'answers',a.answers,'result',a.result,'official_format',a.official_format);
end $$;

create function public.cat_api(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security invoker set search_path='' as $$
declare u cat_private.users; a cat_private.attempts; p cat_private.packages; aid uuid; q jsonb; qs jsonb; r jsonb; prev jsonb; hits integer; qcode text; opt text; req uuid; expected integer; v_writer uuid; ids text[]; target uuid;
begin
 if p_actor is null then raise exception 'AUTH_REQUIRED'; end if;
 insert into cat_private.users(id) values(p_actor) on conflict do nothing;
 select * into u from cat_private.users where id=p_actor;
 if p_action='profile' then return jsonb_build_object('role',u.role,'enabled',u.enabled); end if;
 if not u.enabled then raise exception 'ACCESS_PENDING'; end if;
 insert into cat_private.rate_limits values(p_actor,clock_timestamp(),1) on conflict(actor) do update set hits=case when cat_private.rate_limits.window_at<clock_timestamp()-interval '1 minute' then 1 else cat_private.rate_limits.hits+1 end, window_at=case when cat_private.rate_limits.window_at<clock_timestamp()-interval '1 minute' then clock_timestamp() else cat_private.rate_limits.window_at end returning rate_limits.hits into hits;
 if hits>180 then raise exception 'RATE_LIMIT'; end if;
 if p_action='packages' then return coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'mode',mode,'duration',duration,'count',cardinality(codes),'official_format',official_format)) from cat_private.packages where published),'[]'); end if;
 if p_action='history' then
  for aid in select id from cat_private.attempts where user_id=p_actor and status='active' and expires_at<=clock_timestamp() loop perform cat_private.finish(aid,'expired'); end loop;
  return coalesce((select jsonb_agg(t) from (select id,title,mode,status,started_at,expires_at,result from cat_private.attempts where user_id=p_actor order by started_at desc limit 50)t),'[]');
 end if;
 if p_action='start' then
  perform pg_advisory_xact_lock(hashtextextended(p_actor::text,0));
  req:=(p_data->>'request_id')::uuid; v_writer:=(p_data->>'writer')::uuid;
  if req is null or v_writer is null then raise exception 'INVALID_REQUEST'; end if;
  select * into a from cat_private.attempts where user_id=p_actor and request_id=req;
  if found then
   if a.package_id<>p_data->>'package_id' then raise exception 'REQUEST_CONFLICT'; end if;
   if a.status='active' and a.expires_at<=clock_timestamp() then perform cat_private.finish(a.id,'expired'); end if;
   return cat_private.attempt_view(a.id);
  end if;
  for aid in select id from cat_private.attempts where user_id=p_actor and status='active' and expires_at<=clock_timestamp() loop perform cat_private.finish(aid,'expired'); end loop;
  if exists(select 1 from cat_private.attempts where user_id=p_actor and status='active') then raise exception 'ACTIVE_EXISTS'; end if;
  select * into p from cat_private.packages where id=p_data->>'package_id' and published;
  if not found then raise exception 'PACKAGE_UNAVAILABLE'; end if;
  select jsonb_agg(z.payload || jsonb_build_object('code',z.code,'version',z.version) order by k.pos) into qs from unnest(p.codes) with ordinality k(code,pos) join cat_private.questions z on z.code=k.code and not z.archived;
  if coalesce(jsonb_array_length(qs),0)<>cardinality(p.codes) then raise exception 'PACKAGE_INCOMPLETE'; end if;
  insert into cat_private.attempts(user_id,request_id,package_id,title,mode,official_format,expires_at,snapshot,writer) values(p_actor,req,p.id,p.title,p.mode,p.official_format,clock_timestamp()+make_interval(secs=>p.duration),qs,v_writer) returning id into aid;
  return cat_private.attempt_view(aid);
 end if;
 if p_action in ('get','save','finalize','takeover') then
  select * into a from cat_private.attempts where id=(p_data->>'attempt_id')::uuid and user_id=p_actor for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if a.status='active' and a.expires_at<=clock_timestamp() then perform cat_private.finish(a.id,'expired'); return cat_private.attempt_view(a.id); end if;
  if a.status<>'active' or p_action='get' then return cat_private.attempt_view(a.id); end if;
  v_writer:=(p_data->>'writer')::uuid;
  if v_writer is null then raise exception 'INVALID_WRITER'; end if;
  if p_action='takeover' then update cat_private.attempts set writer=v_writer where id=a.id; return cat_private.attempt_view(a.id); end if;
  if v_writer<>a.writer then raise exception 'WRITER_CONFLICT'; end if;
  if p_action='finalize' then perform cat_private.finish(a.id,'submitted'); return cat_private.attempt_view(a.id); end if;
  req:=(p_data->>'request_id')::uuid; if req is null then raise exception 'INVALID_REQUEST'; end if;
  select payload into prev from cat_private.receipts where attempt_id=a.id and request_id=req;
  if found then if prev<>p_data then raise exception 'REQUEST_CONFLICT'; end if; return cat_private.attempt_view(a.id); end if;
  expected:=(p_data->>'revision')::int;
  if expected is null or expected<>a.revision then raise exception 'REVISION_CONFLICT'; end if;
  qcode:=p_data->>'code'; opt:=p_data->>'option';
  select value into q from jsonb_array_elements(a.snapshot) where value->>'code'=qcode;
  if q is null or not exists(select 1 from jsonb_array_elements(q->'options') o where o->>'id'=opt) then raise exception 'INVALID_OPTION'; end if;
  if a.mode='learn' and a.answers ? qcode then raise exception 'ANSWER_LOCKED'; end if;
  update cat_private.attempts set answers=jsonb_set(answers,array[qcode],jsonb_build_object('option',opt,'saved_at',clock_timestamp())),revision=revision+1 where id=a.id;
  insert into cat_private.receipts values(a.id,req,p_data);
  return cat_private.attempt_view(a.id);
 end if;
 if u.role not in ('admin','owner') then raise exception 'FORBIDDEN'; end if;
 if p_action='admin_questions' then return coalesce((select jsonb_agg(t) from (select code,version,payload,archived from cat_private.questions order by code limit 1000)t),'[]'); end if;
 if p_action='admin_packages' then return coalesce((select jsonb_agg(t) from cat_private.packages t),'[]'); end if;
 if p_action='admin_users' then return coalesce((select jsonb_agg(t) from (select c.id,c.role,c.enabled,c.created_at,a.email from cat_private.users c join auth.users a on a.id=c.id order by c.created_at desc limit 200)t),'[]'); end if;
 if p_action='admin_results' then return coalesce((select jsonb_agg(t) from (select id,user_id,title,status,started_at,result from cat_private.attempts order by started_at desc limit 200)t),'[]'); end if;
 if p_action='admin_import' then
  if jsonb_typeof(p_data->'questions')<>'array' or jsonb_array_length(p_data->'questions') not between 1 and 200 then raise exception 'INVALID_BATCH'; end if;
  if (select count(distinct value->>'code') from jsonb_array_elements(p_data->'questions'))<>jsonb_array_length(p_data->'questions') then raise exception 'DUPLICATE_CODES'; end if;
  for q in select value from jsonb_array_elements(p_data->'questions') loop
   if not cat_private.validate_question(q) or coalesce(q->>'code','') !~ '^[A-Za-z0-9_-]{1,40}$' then raise exception 'INVALID_QUESTION: %',q->>'code'; end if;
   insert into cat_private.questions(code,payload) values(q->>'code',q) on conflict(code) do update set payload=excluded.payload,version=cat_private.questions.version+1,updated_at=clock_timestamp();
  end loop;
  insert into cat_private.audit(actor,action,detail) values(p_actor,p_action,jsonb_build_object('count',jsonb_array_length(p_data->'questions')));
  return jsonb_build_object('ok',true);
 end if;
 if p_action='admin_archive' then
  insert into cat_private.audit(actor,action,detail) values(p_actor,p_action,jsonb_build_object('code',p_data->>'code','archived',p_data->'archived'));
  update cat_private.questions set archived=coalesce((p_data->>'archived')::boolean,true) where code=p_data->>'code';
  return jsonb_build_object('ok',true);
 end if;
 if p_action='admin_package' then
  ids:=array(select jsonb_array_elements_text(p_data->'codes'));
  if cardinality(ids) not between 1 and 200 or cardinality(ids)<>(select count(distinct x) from unnest(ids)x) then raise exception 'INVALID_CODES'; end if;
  if (select count(*) from cat_private.questions where code=any(ids) and not archived)<>cardinality(ids) then raise exception 'PACKAGE_INCOMPLETE'; end if;
  if coalesce((p_data->>'official_format')::bool,false) then
   if cardinality(ids)<>110 or (p_data->>'duration')::int<>6000 or p_data->>'mode'<>'exam' or (select count(*) from cat_private.questions where code=any(ids) and payload->>'category'='TWK')<>30 or (select count(*) from cat_private.questions where code=any(ids) and payload->>'category'='TIU')<>35 then raise exception 'INVALID_OFFICIAL_FORMAT'; end if;
  end if;
  if coalesce(length(p_data->>'title'),0) not between 3 and 160 or coalesce(p_data->>'id','') !~ '^[a-z0-9_-]{1,60}$' then raise exception 'INVALID_PACKAGE'; end if;
  insert into cat_private.packages values(p_data->>'id',p_data->>'title',p_data->>'mode',(p_data->>'duration')::int,ids,coalesce((p_data->>'published')::bool,false),coalesce((p_data->>'official_format')::bool,false)) on conflict(id) do update set title=excluded.title,mode=excluded.mode,duration=excluded.duration,codes=excluded.codes,published=excluded.published,official_format=excluded.official_format;
  insert into cat_private.audit(actor,action,detail) values(p_actor,p_action,jsonb_build_object('id',p_data->>'id'));
  return jsonb_build_object('ok',true);
 end if;
 if p_action='admin_access' then
  target:=(p_data->>'user_id')::uuid;
  if target=p_actor or exists(select 1 from cat_private.users where id=target and role<>'participant') then raise exception 'PROTECTED_USER'; end if;
  update cat_private.users set enabled=(p_data->>'enabled')::bool where id=target;
  insert into cat_private.audit(actor,action,detail) values(p_actor,p_action,jsonb_build_object('target',target,'enabled',p_data->'enabled'));
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'UNKNOWN_ACTION';
end $$;
revoke all on all functions in schema cat_private from public,anon,authenticated;
grant execute on all functions in schema cat_private to service_role;
revoke all on function public.cat_api(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.cat_api(uuid,text,jsonb) to service_role;
commit;
