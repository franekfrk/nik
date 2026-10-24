'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs'),path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../panel/static/app.js'),'utf8');
function setup(){
 const nodes=new Map(),rendered=[],progress=[],calls=[],messages=[];
 const node=selector=>{if(!nodes.has(selector))nodes.set(selector,{hidden:false,open:false,textContent:'',className:'',replaceChildren(){},showModal(){this.open=true;}});return nodes.get(selector);};
 const context=vm.createContext({$:node,currentJob:{id:'active',key:'key',label:'Plecak',action:'inventory'},resultTarget:null,polling:false,sessionStorage:{removeItem(){}},icon:()=>({}),resetRichResult(){},renderLiveProgress:j=>progress.push(j.id),renderFinishedResult:j=>rendered.push(j.id),refreshHistory(){},refreshBackups(){},toast:s=>messages.push(s),watchArchivedProgress(){},setTimeout:f=>f(),api:async url=>{calls.push(url);return {id:url.split('/').at(-1),state:'success',output:'saved',label:'Zapisany wynik'};}});
 for(const name of ['showResult','poll','openHistoryResult','finish']){
  const start=source.indexOf((name==='poll'||name==='openHistoryResult'?'async ':'')+'function '+name+'(');assert(start>=0);
  let end=source.indexOf('\n',start);if(name==='openHistoryResult')end=source.indexOf('\nfunction finish(',start);
  vm.runInContext(source.slice(start,end),context);
 }
 return {context,nodes,rendered,progress,calls,messages};
}
test('completed history opens while another task is running, without resubmission',async()=>{const t=setup();await t.context.openHistoryResult({id:'old'});assert.deepEqual(t.rendered,['old']);assert.equal(t.context.currentJob.id,'active');assert.equal(t.context.resultTarget,'old');assert.deepEqual(t.calls,['/api/history/old']);});
test('background completion preserves the historical result on screen',async()=>{const t=setup();await t.context.openHistoryResult({id:'old'});await t.context.poll();assert.deepEqual(t.rendered,['old']);assert.deepEqual(t.progress,[]);assert.equal(t.context.currentJob,null);assert.equal(t.context.resultTarget,'old');assert.equal(t.messages.length,1);});
test('returning to current task renders its result normally',async()=>{const t=setup();await t.context.openHistoryResult({id:'old'});t.context.showResult();await t.context.poll();assert.deepEqual(t.rendered,['old','active']);assert.deepEqual(t.progress,['active']);});
test('stale history response cannot replace a newly selected current task',async()=>{const t=setup();let resolve;t.context.api=()=>new Promise(r=>{resolve=r;});const pending=t.context.openHistoryResult({id:'old'});t.context.showResult();resolve({id:'old',state:'success'});await pending;assert.deepEqual(t.rendered,[]);assert.equal(t.context.resultTarget,'current');});
test('background transport error cannot overwrite the displayed history',async()=>{const t=setup();await t.context.openHistoryResult({id:'old'});t.context.$('#result-message').textContent='Historical result';t.context.api=async()=>{throw Error('network');};await t.context.poll();assert.equal(t.nodes.get('#result-message').textContent,'Historical result');assert.deepEqual(t.rendered,['old']);});
test('late job response after logout does not access cleared current task',async()=>{const t=setup();let resolve;t.context.api=()=>new Promise(r=>{resolve=r;});const pending=t.context.poll();t.context.currentJob=null;resolve({id:'active',state:'success'});await pending;assert.deepEqual(t.rendered,[]);});
