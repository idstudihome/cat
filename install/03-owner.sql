-- Jalankan sekali setelah akun pemilik dibuat di Supabase Auth.
-- Ganti OWNER_UUID dengan User UID pemilik dari Authentication > Users.
insert into cat_private.users (id, role, enabled)
select 'OWNER_UUID'::uuid, 'owner', true
where exists (select 1 from auth.users where id = 'OWNER_UUID'::uuid)
on conflict (id) do update set role = 'owner', enabled = true, updated_at = now();
