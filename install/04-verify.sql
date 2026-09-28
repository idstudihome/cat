-- Pemeriksaan cepat setelah 01-database.sql, 02-seed.sql, dan 03-owner.sql.
-- Catatan skema: kategori soal tersimpan di dalam kolom payload (payload->>'category'),
-- bukan sebagai kolom terpisah. Kolom daftar soal pada paket bernama codes (text[]).
-- Hasil yang diharapkan: 110 soal total (TWK 30, TIU 35, TKP 45).
select count(*) as total_questions from cat_private.questions;

select payload->>'category' as category, count(*) as jumlah
from cat_private.questions
group by 1
order by 1;

select id, title, cardinality(codes) as question_count
from cat_private.packages
order by id;

select id, role, enabled from cat_private.users order by created_at;
