import { createClient } from 'npm:@supabase/supabase-js@2.117.2';
const headers={'Content-Type':'application/json','Cache-Control':'no-store','Vary':'Origin'};
Deno.serve(async(req:Request)=>{
 const origin=req.headers.get('Origin')||'';
 const allow=(Deno.env.get('ALLOWED_ORIGINS')||'').split(',').map(x=>x.trim());
 const cors=allow.includes(origin)?{'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS'}:{};
 const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...headers,...cors}});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:{...headers,...cors}});
 if(req.method!=='POST')return reply({error:'METHOD_NOT_ALLOWED'},405);
 if(origin&&!allow.includes(origin))return reply({error:'ORIGIN_NOT_ALLOWED'},403);
 try{
  if(Number(req.headers.get('content-length')||0)>800000)return reply({error:'BODY_TOO_LARGE'},413);
  const raw=await req.text();if(raw.length>800000)return reply({error:'BODY_TOO_LARGE'},413);
  const token=req.headers.get('Authorization')?.replace(/^Bearer /,'');
  if(!token)return reply({error:'AUTH_REQUIRED'},401);
  const client=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:{user},error:authError}=await client.auth.getUser(token);
  if(authError||!user)return reply({error:'AUTH_REQUIRED'},401);
  const body=JSON.parse(raw);
  if(typeof body.action!=='string'||!body.data||typeof body.data!=='object'||Array.isArray(body.data))return reply({error:'INVALID_REQUEST'},422);
  const {data,error}=await client.rpc('cat_api',{p_actor:user.id,p_action:body.action,p_data:body.data});
  if(error){
   const code=error.message.split(':')[0];
   const known=['ACCESS_PENDING','FORBIDDEN','NOT_FOUND','ACTIVE_EXISTS','REVISION_CONFLICT','WRITER_CONFLICT','REQUEST_CONFLICT','ANSWER_LOCKED','INVALID_OPTION','INVALID_REQUEST','INVALID_WRITER','INVALID_BATCH','INVALID_QUESTION','INVALID_PACKAGE','INVALID_CODES','INVALID_OFFICIAL_FORMAT','PACKAGE_INCOMPLETE','PACKAGE_UNAVAILABLE','PROTECTED_USER','UNKNOWN_ACTION','RATE_LIMIT'];
   return reply({error:known.includes(code)?code:'SERVER_ERROR'},code==='RATE_LIMIT'?429:code==='ACCESS_PENDING'||code==='FORBIDDEN'?403:code.includes('CONFLICT')||code==='ACTIVE_EXISTS'?409:known.includes(code)?422:500);
  }
  return reply({data});
 }catch{return reply({error:'INVALID_REQUEST'},422);}
});
