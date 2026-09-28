import {afterAll,beforeAll,describe,it,expect} from 'vitest';
import {PGlite} from '@electric-sql/pglite';import{readFileSync}from'node:fs';import{randomUUID}from'node:crypto';
// Mengunci dua regresi yang pernah terjadi:
// 1. 03-owner.sql menyentuh kolom updated_at yang tidak ada pada cat_private.users.
// 2. 04-verify.sql membaca kolom category / question_codes yang tidak ada pada skema asli.
let db:PGlite;let owner:string;
const ownerSql=()=>readFileSync('install/03-owner.sql','utf8').replaceAll('OWNER_UUID',owner);
const EXPECTED_PACKAGES:Record<string,number>={'latihan-100':100,'simulasi-110':110,'tiu-35':35,'tkp-45':45,'twk-30':30};
beforeAll(async()=>{db=new PGlite();await db.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key,email text);');await db.exec(readFileSync('install/01-database.sql','utf8'));await db.exec(readFileSync('install/02-seed.sql','utf8'));owner=randomUUID();await db.query('insert into auth.users values($1,$2)',[owner,owner+'@example.invalid']);},30000);
afterAll(async()=>{await db.close();});
describe('Skrip instalasi cocok dengan skema asli',()=>{
 it('03-owner.sql menjadikan akun Auth sebagai owner tanpa kolom yang tidak ada',async()=>{await db.exec(ownerSql());const r=await db.query<any>('select role,enabled from cat_private.users where id=$1',[owner]);expect(r.rows[0]).toEqual({role:'owner',enabled:true});});
 it('03-owner.sql dapat dijalankan ulang tanpa menggandakan baris',async()=>{await db.exec(ownerSql());const r=await db.query<any>('select count(*)::int n from cat_private.users where id=$1',[owner]);expect(r.rows[0].n).toBe(1);});
 it('04-verify.sql berjalan dan melaporkan bank soal yang benar',async()=>{const res=await db.exec(readFileSync('install/04-verify.sql','utf8'));expect(res[0].rows[0]).toEqual({total_questions:110});expect(res[1].rows).toEqual([{category:'TIU',jumlah:35},{category:'TKP',jumlah:45},{category:'TWK',jumlah:30}]);expect(Object.fromEntries((res[2].rows as any[]).map(r=>[r.id,r.question_count]))).toEqual(EXPECTED_PACKAGES);expect(res[3].rows[0]).toMatchObject({role:'owner',enabled:true});});
});
