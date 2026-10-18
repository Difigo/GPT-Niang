import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {atomicJson} from './usage.mjs';
import {readJson} from './worker-state.mjs';

export const defaultPersona=fs.readFileSync(new URL('../assets/quote-persona.txt',import.meta.url),'utf8').trim();
export const generationDefaults=Object.freeze({enabled:false,threshold:20,batchSize:43,maxDaily:2,minIntervalMinutes:30,model:'',persona:defaultPersona});
export function normalizeGenerationSettings(value={}) {
  const number=(key,min,max)=>Number.isSafeInteger(value?.[key]) && value[key]>=min && value[key]<=max?value[key]:generationDefaults[key];
  return {enabled:value?.enabled===true,threshold:number('threshold',1,1000),batchSize:number('batchSize',1,200),maxDaily:number('maxDaily',1,100),
    minIntervalMinutes:number('minIntervalMinutes',1,1440),model:typeof value?.model==='string' && /^[A-Za-z0-9._:/-]{0,160}$/.test(value.model)?value.model:'',
    persona:typeof value?.persona==='string' && value.persona.trim() && value.persona.length<=6000?value.persona.trim():defaultPersona,
    revision:typeof value?.revision==='string'?value.revision:''};
}
export function quoteKey(text) {
  return createHash('sha256').update(text.normalize('NFKC').replace(/\s+/gu,'')).digest('hex');
}
export function quoteRows(value) {
  const rows=Array.isArray(value)?value:value?.quotes;
  if(!Array.isArray(rows))return [];
  const result=[],keys=new Set();
  for(const row of rows){
    const raw=typeof row==='string'?row:row?.text;
    const text=typeof raw==='string'?raw.trim():null;
    const weight=typeof row==='string'?1:(row?.weight??1);
    if(typeof text!=='string' || !text || text.length>200 || /[\x00-\x08\x0B\x0C\x0E-\x1F]/u.test(text) || !Number.isFinite(weight) || weight<=0 || weight>1000)continue;
    const key=quoteKey(text);
    if(!keys.has(key)){keys.add(key);result.push({text,weight});}
  }
  return result;
}
export function readQuoteInventory(dataDir,builtIn) {
  let base=quoteRows(readJson(path.join(dataDir,'quotes.json')));
  if(!base.length)base=quoteRows(readJson(builtIn));
  return {base,generated:quoteRows(readJson(path.join(dataDir,'generated-quotes.json'))),shown:readJson(path.join(dataDir,'quote-history.json'))?.shown??{}};
}
export function unseenQuotes(inventory) {
  return quoteRows([...inventory.base,...inventory.generated]).filter(row=>!Object.hasOwn(inventory.shown,quoteKey(row.text)));
}
export function validateGeneratedQuotes(value,existing=[],limit=200) {
  const keys=new Set(existing.map(row=>quoteKey(row.text))),accepted=[];
  for(const row of quoteRows(value)){
    const text=row.text;
    if([...text].length>40 || /[\r\n\t]|https?:\/\/|```|^\s*(?:[-*#]|\d+[.)、])/u.test(text))continue;
    const key=quoteKey(text);
    if(keys.has(key))continue;
    keys.add(key);accepted.push({text,weight:1});
    if(accepted.length>=limit)break;
  }
  return accepted;
}
export function localDay(now) {
  const date=new Date(now);
  return [date.getFullYear(),String(date.getMonth()+1).padStart(2,'0'),String(date.getDate()).padStart(2,'0')].join('-');
}

// Only the existing single-owner Windows worker creates this controller. UI owns
// history/settings; this controller alone owns generated stock and its budget.
export function createQuoteReplenisher({dataDir,builtIn,generate,clock=Date.now,platform=process.platform}) {
  const settingsFile=path.join(dataDir,'quote-generation.json'),stateFile=path.join(dataDir,'quote-generation-state.json');
  let active=null,closed=false;
  const settings=()=>normalizeGenerationSettings(readJson(settingsFile));
  const publish=(patch)=>atomicJson(stateFile,{...(readJson(stateFile)??{}),...patch,at:clock()});
  // The single-owner lock has already been acquired. Never leave a crashed
  // invocation looking active, and never refund its reserved daily attempt.
  if(readJson(stateFile)?.status==='generating'){try{publish({status:'cancelled',added:0});}catch{}}
  function cancel(){if(active)active.controller.abort();}
  function tick({visible=false,ownerPid=null}={}) {
    if(closed)return;
    const config=settings(),now=clock();
    if(active){
      if(!config.enabled || config.revision!==active.revision || !visible || ownerPid!==active.ownerPid)cancel();
      return active.promise;
    }
    if(platform!=='win32' || !config.enabled || !visible)return;
    const previous=readJson(stateFile)??{},day=localDay(now);
    if(fs.existsSync(stateFile) && !readJson(stateFile))return;
    // A backwards clock must not reset the cap or bypass the cooldown.
    const count=typeof previous.day==='string' && previous.day>=day?(previous.attempts??0):0;
    if(count>=config.maxDaily || (Number.isFinite(previous.lastAttempt) && now-previous.lastAttempt<config.minIntervalMinutes*60000))return;
    const inventory=readQuoteInventory(dataDir,builtIn);
    if(unseenQuotes(inventory).length>=config.threshold)return;
    const controller=new AbortController(),job={controller,revision:config.revision,ownerPid,promise:null};
    active=job;
    // Reserve before touching the model: failures, cancellation and restarts count.
    try{publish({day:previous.day>day?previous.day:day,attempts:count+1,lastAttempt:now,status:'generating',added:0});}
    catch{active=null;return;}
    const poll=setInterval(()=>{
      const latest=settings();
      if(closed || !latest.enabled || latest.revision!==job.revision)cancel();
    },200);
    job.promise=(async()=>{
      try{
        const samples=inventory.base.length<=16?inventory.base:Array.from({length:16},(_,i)=>inventory.base[Math.floor(i*(inventory.base.length-1)/15)]);
        const result=await generate({settings:config,samples:samples.map(row=>row.text),signal:controller.signal});
        const latest=settings();
        if(closed || controller.signal.aborted || !latest.enabled || latest.revision!==job.revision){publish({status:'cancelled'});return;}
        const current=readQuoteInventory(dataDir,builtIn);
        const rows=validateGeneratedQuotes(result,[...current.base,...current.generated],config.batchSize);
        if(!rows.length)throw new Error('NO_VALID_QUOTES');
        atomicJson(path.join(dataDir,'generated-quotes.json'),{version:1,quotes:[...current.generated,...rows]});
        publish({status:'ready',added:rows.length});
      }catch(error){
        // Do not persist model stderr, prompts, account details or arbitrary errors.
        publish({status:controller.signal.aborted?'cancelled':'failed',error:controller.signal.aborted?null:(error?.code==='AUTH_REQUIRED'?'AUTH_REQUIRED':'GENERATION_FAILED')});
      }finally{clearInterval(poll);if(active===job)active=null;}
    })().catch(()=>{});
    return job.promise;
  }
  return {tick,cancel,close(){closed=true;cancel();},get busy(){return active!==null;}};
}
