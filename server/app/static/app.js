'use strict';
const $ = id => document.getElementById(id);
let offset = 0, total = 0, sources = [], browsePath = null, polling = null, lastScan = null, sourceSnapshot = '';
const statusNames = {running:'Выполняется',completed:'Завершено',partial:'Есть ошибки',failed:'Не завершено',interrupted:'Прервано перезапуском'};
function node(tag, text, cls) { const el = document.createElement(tag); if (text !== undefined) el.textContent = text; if(cls) el.className = cls; return el; }
function notify(message) { $('notice').textContent = message; $('notice').hidden = false; }
function clearNotice() { $('notice').hidden = true; }
async function api(path, options = {}) {
  const response = await fetch(path, {credentials:'same-origin', ...options, headers:{'Content-Type':'application/json','X-Detox-Admin':'1',...options.headers}});
  if (!response.ok) {
    let message = `Ошибка ${response.status}`;
    try { const data = await response.json(); if(typeof data.detail === 'string') message = data.detail; } catch {}
    if(response.status === 401) showLogin();
    throw new Error(message);
  }
  return response.json();
}
function action(fn) { return async event => { event?.preventDefault(); clearNotice(); try { await fn(event); } catch(error) { notify(error.message); } }; }
function showLogin() { $('login').hidden=false; $('dashboard').hidden=true; $('logout').hidden=true; clearInterval(polling); polling=null; $('key-value').textContent=''; $('new-key').hidden=true; if($('folder-dialog').open) $('folder-dialog').close(); }
async function showDashboard() {
  await refreshState();
  $('login').hidden=true; $('dashboard').hidden=false; $('logout').hidden=false;
  await Promise.all([loadCatalog(), loadKeys()]);
  if(!polling) polling=setInterval(() => refreshState().catch(error => notify(error.message)), 2000);
}
function button(text, fn, cls) { const el=node('button',text,cls); el.type='button'; el.addEventListener('click',action(fn)); return el; }
async function refreshState() {
  const state = await api('/admin/state'); sources=state.sources;
  $('source-count').textContent=sources.length;
  $('track-count').textContent=sources.reduce((sum,s)=>sum+s.tracks,0).toLocaleString('ru');
  const busy=state.scan?.status==='running';
  $('refresh').disabled=busy || !sources.length; $('reset').disabled=busy || !sources.length; $('add-source').disabled=busy;
  const snapshot=JSON.stringify({sources,busy});
  if(snapshot!==sourceSnapshot) {
  sourceSnapshot=snapshot;
  const sourceList=$('sources'); sourceList.replaceChildren();
  if(!sources.length) sourceList.append(node('p','Пока нет источников. Добавь первую папку с музыкой.'));
  for(const source of sources) {
    const row=node('div',undefined,'source-row'); row.append(node('span','♫','source-icon'));
    const info=node('div',undefined,'row-info'); info.append(node('strong',source.name),node('small',source.path),node('small',`${source.tracks.toLocaleString('ru')} треков · ${source.available?'Папка доступна':'Папка недоступна'}`));
    if(source.error) info.append(node('small',source.error,'warning'));
    row.append(info);
    const scan=button('Пересканировать',()=>startScan(source.id)); scan.disabled=busy; row.append(scan);
    row.append(button('Убрать',async()=>{
      if(!confirm(`Убрать «${source.name}» из библиотеки (${source.tracks} треков)? Файлы на диске останутся. Записи в плейлистах могут стать недоступными.`)) return;
      await api(`/admin/sources/${source.id}`,{method:'DELETE'}); offset=0; await refreshState(); await loadCatalog();
    },'danger')); sourceList.append(row);
  }
  const selected=$('source-filter').value;
  $('source-filter').replaceChildren(new Option('Все источники',''),...sources.map(s=>new Option(s.name,s.id)));
  if(sources.some(s=>s.id===selected)) $('source-filter').value=selected;
  }
  const scan=state.scan;
  $('scan-status').textContent=scan?statusNames[scan.status] || scan.status:'Не запускалось';
  $('scan-progress').textContent=scan?`Обработано файлов: ${scan.processed}`:'';
  $('scan-summary').textContent=scan?`${scan.mode==='reset'?'Полная переиндексация':'Пересканирование'} · ${new Date(scan.started_at).toLocaleString('ru')} · ${statusNames[scan.status] || scan.status}. Обработано: ${scan.processed}. Ошибки: ${scan.errors.length}${scan.errors.length>=100?' (показаны первые 100)':''}.`:'Сканирование ещё не запускалось.';
  $('scan-errors').replaceChildren(...(scan?.errors || []).map(e=>node('li',`${e.path || sources.find(s=>s.id===e.source_id)?.name || 'Источник'}: ${e.message}`)));
  const signature=scan?`${scan.id}:${scan.status}`:'';
  if(lastScan!==signature) { lastScan=signature; await loadCatalog(); }
}
async function startScan(sourceId=null, reset=false) { await api('/admin/scans',{method:'POST',body:JSON.stringify({source_id:sourceId,reset})}); await refreshState(); }
async function loadCatalog() {
  const params=new URLSearchParams({q:$('search').value,offset:String(offset),limit:'50'});
  const source=$('source-filter').value, folder=$('folder-filter').value;
  if(source) params.set('source_id',source);
  if(folder) params.set('folder',folder);
  const catalog=await api(`/admin/tracks?${params}`); total=catalog.total;
  const folderNames=[...new Set(catalog.folders.filter(f=>!source || f.source_id===source).map(f=>f.folder))].sort((a,b)=>a.localeCompare(b,'ru'));
  $('folder-filter').replaceChildren(new Option('Все папки',''),...folderNames.map(f=>new Option(f==='.'?'Корень источника':f,f)));
  if(folderNames.includes(folder)) $('folder-filter').value=folder;
  const folderQuery=$('search').value.toLocaleLowerCase('ru');
  const matchingFolders=catalog.folders.filter(f=>(!source || f.source_id===source) && `${f.source_name} ${f.folder}`.toLocaleLowerCase('ru').includes(folderQuery));
  $('folder-summary').textContent=`Просканированные папки: ${matchingFolders.length}`;
  $('catalog-folders').replaceChildren(...matchingFolders.slice(0,100).map(f=>button(`${f.source_name} / ${f.folder==='.'?'(корень)':f.folder}`,async()=>{
    $('source-filter').value=f.source_id;
    if(![...$('folder-filter').options].some(option=>option.value===f.folder)) $('folder-filter').add(new Option(f.folder,f.folder));
    $('folder-filter').value=f.folder; offset=0; await loadCatalog();
  })));
  if(matchingFolders.length>100) $('catalog-folders').append(node('p','Показаны первые 100 папок. Уточни поиск, чтобы найти нужную.'));
  if(!matchingFolders.length) $('catalog-folders').append(node('p','Папки не найдены.'));
  const tbody=$('tracks'); tbody.replaceChildren();
  for(const track of catalog.items) {
    const row=node('tr'); const title=node('td'); title.append(node('strong',track.title));
    if(track.error) title.append(node('small',track.error,'warning'));
    const artist=node('td'); artist.append(node('span',track.artist),node('small',track.album || 'Без альбома'));
    const path=node('td'); path.append(node('span',track.source_name),node('small',track.path));
    const size=node('td'); size.append(node('span',`${(track.size/1048576).toFixed(1)} МБ`));
    if(track.duration) size.append(node('small',`${Math.floor(track.duration/60)}:${String(Math.floor(track.duration%60)).padStart(2,'0')}`));
    row.append(title,artist,path,size); tbody.append(row);
  }
  if(!catalog.items.length) { const row=node('tr'),cell=node('td','Ничего не найдено. Добавь папку или измени условия поиска.'); cell.colSpan=4; row.append(cell); tbody.append(row); }
  $('results').textContent=total?`${offset+1}–${Math.min(offset+50,total)} из ${total.toLocaleString('ru')}`:'0 файлов';
  $('prev').disabled=offset===0; $('next').disabled=offset+50>=total;
}
async function browse(path=null) {
  const result=await api('/admin/browse'+(path!==null?'?'+new URLSearchParams({path}):'')); browsePath=result.path;
  $('browse-path').textContent=result.path || 'Разрешённые каталоги Docker';
  $('browse-up').onclick=action(()=>browse(result.parent)); $('browse-up').disabled=result.path===null;
  $('confirm-folder').disabled=result.path===null;
  $('folder-list').replaceChildren(...result.folders.map(folder=>{
    const el=button(`▸ ${folder.name}${folder.available?'':' — недоступно'}`,()=>browse(folder.path)); el.disabled=!folder.available; return el;
  }));
  if(!result.folders.length) $('folder-list').append(node('p','Вложенных папок нет. Можно добавить текущую папку.'));
}
async function loadKeys() {
  const keys=await api('/admin/keys'); $('keys').replaceChildren();
  if(!keys.length) $('keys').append(node('p','Ключи пока не выданы.'));
  for(const key of keys) {
    const row=node('div',undefined,'key-row'), info=node('div',undefined,'row-info');
    info.append(node('strong',key.name),node('small',`${new Date(key.created_at).toLocaleString('ru')} · ${key.revoked_at?'Отозван':'Активен'}`)); row.append(info);
    if(!key.revoked_at) row.append(button('Отозвать',async()=>{
      if(!confirm(`Отозвать ключ «${key.name}»?`)) return;
      await api(`/admin/keys/${key.id}`,{method:'DELETE'}); await loadKeys();
    },'danger'));
    $('keys').append(row);
  }
}
$('login-form').addEventListener('submit',action(async()=>{ await api('/admin/login',{method:'POST',body:JSON.stringify({secret:$('secret').value})}); $('secret').value=''; await showDashboard(); }));
$('logout').addEventListener('click',action(async()=>{ await api('/admin/logout',{method:'POST'}); showLogin(); }));
$('refresh').addEventListener('click',action(()=>startScan()));
$('reset').addEventListener('click',action(async()=>{ if(confirm('Перестроить весь индекс? Файлы, источники и ключи останутся. Старый каталог будет заменён после успешного обхода папок. Это может занять время.')) await startScan(null,true); }));
$('add-source').addEventListener('click',action(async()=>{ $('source-name').value=''; await browse(); $('folder-dialog').showModal(); }));
$('close-dialog').addEventListener('click',()=>$('folder-dialog').close());
$('confirm-folder').addEventListener('click',action(async()=>{ if(!browsePath) return; $('confirm-folder').disabled=true; try { await api('/admin/sources',{method:'POST',body:JSON.stringify({name:$('source-name').value,path:browsePath})}); $('folder-dialog').close(); offset=0; await refreshState(); } finally { $('confirm-folder').disabled=false; } }));
$('search-form').addEventListener('submit',action(async()=>{ offset=0; await loadCatalog(); }));
$('source-filter').addEventListener('change',action(async()=>{ offset=0; $('folder-filter').value=''; await loadCatalog(); }));
$('folder-filter').addEventListener('change',action(async()=>{ offset=0; await loadCatalog(); }));
$('prev').addEventListener('click',action(async()=>{ offset=Math.max(0,offset-50); await loadCatalog(); }));
$('next').addEventListener('click',action(async()=>{ offset+=50; await loadCatalog(); }));
$('key-form').addEventListener('submit',action(async()=>{ const result=await api('/admin/keys',{method:'POST',body:JSON.stringify({name:$('key-name').value})}); $('key-name').value=''; $('key-value').textContent=result.key; $('new-key').hidden=false; await loadKeys(); }));
$('hide-key').addEventListener('click',()=>{ $('key-value').textContent=''; $('new-key').hidden=true; });
showDashboard().catch(error=>{showLogin(); if(!error.message.includes('Войдите')) notify(error.message);});
