export type Option={id:string;text:string;score?:number;reason?:string};
export type Question={code:string;category:'TWK'|'TIU'|'TKP';topic:string;stem:string;options:Option[];explanation?:string;tip?:string};
export type Result={TWK:number;TIU:number;TKP:number;total:number;maximum:number;answered:number;count:number;counts:Record<string,number>;passed:boolean|null;finished_at:string};
export type Attempt={id:string;title:string;mode:'learn'|'exam';status:'active'|'submitted'|'expired';expires_at:string;started_at:string;server_now:string;revision:number;questions:Question[];answers:Record<string,{option:string;saved_at:string}>;result:Result|null;official_format:boolean};
export type Package={id:string;title:string;mode:'learn'|'exam';duration:number;count:number;official_format:boolean};
