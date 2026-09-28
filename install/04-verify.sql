-- Pemeriksaan cepat setelah 01-database.sql, 02-seed.sql, dan 03-owner.sql.
select count(*) as total_questions from cat_private.questions;
select category, count(*) from cat_private.questions group by category order by category;
select code, title, count(*) as question_count from cat_private.packages p
left join lateral jsonb_array_elements_text(p.question_codes) codes(code) on true
group by code, title order by code;
select id, role, enabled from cat_private.users order by created_at;
