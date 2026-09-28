import { createClient } from '@supabase/supabase-js';
const url=import.meta.env.VITE_SUPABASE_URL;const key=import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
const functionUrl =
  import.meta.env.VITE_API_FUNCTION_URL ||
  `${url || ''}/functions/v1/cat-api`;
export const configured=!!url&&!!key;
export const supabase=configured?createClient(url,key):null;
const messages:Record<string,string>={ACCESS_PENDING:'Akun menunggu aktivasi pengelola.',AUTH_REQUIRED:'Sesi login berakhir. Silakan masuk kembali.',ACTIVE_EXISTS:'Masih ada sesi aktif. Lanjutkan dari Riwayat.',REVISION_CONFLICT:'Jawaban berubah di perangkat lain. Muat ulang sesi sebelum menyimpan.',WRITER_CONFLICT:'Sesi sedang digunakan tab lain. Klik Ambil alih sesi untuk melanjutkan di sini.',ANSWER_LOCKED:'Jawaban latihan sudah diperiksa dan tidak dapat diubah.',ORIGIN_NOT_ALLOWED:'Alamat website belum diizinkan pada pengaturan backend.',PACKAGE_INCOMPLETE:'Ada soal paket yang diarsipkan. Hubungi pengelola.',RATE_LIMIT:'Terlalu banyak permintaan. Tunggu sebentar.',FORBIDDEN:'Akun ini tidak memiliki izin.',INVALID_QUESTION:'Format soal belum valid. Periksa opsi, bobot, dan pembahasan.'};
export async function api<T>(action:string,data:Record<string,unknown>={}):Promise<T>{
 if(!supabase)throw new Error('Koneksi Supabase belum dikonfigurasi.');
 const {data:session}=await supabase.auth.getSession();
 if(!session.session)throw new Error(messages.AUTH_REQUIRED);
 let response:Response;
 try{response=await fetch(functionUrl,{method:'POST',headers:{'Content-Type':'application/json',apikey:key,Authorization:`Bearer ${session.session.access_token}`},body:JSON.stringify({action,data})});}
 catch{throw new Error('Tidak dapat menghubungi server. Periksa koneksi internet dan alamat function backend.');}
 const text=await response.text();let body:{error?:string;data?:unknown}={};
 try{body=text?JSON.parse(text) as {error?:string;data?:unknown}:{};}catch{body={};}
 if(!response.ok)throw new Error((body.error&&messages[body.error])||`Permintaan belum berhasil (${body.error||response.status}).`);
 if(!('data'in body))throw new Error('Balasan server tidak dikenali. Periksa alamat Edge Function cat-api dan daftar ALLOWED_ORIGINS.');
 return body.data as T;
}
export const writer=crypto.randomUUID();
export function remaining(expires:string,server:string,anchor:number,now=performance.now()){return Math.max(0,Math.ceil((Date.parse(expires)-Date.parse(server)-(now-anchor))/1000));}
export function clock(n:number){return `${String(Math.floor(n/60)).padStart(2,'0')}:${String(n%60).padStart(2,'0')}`;}
