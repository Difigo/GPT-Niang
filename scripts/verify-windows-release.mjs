// Exercise the real release bytes against the updater's package validator and
// its installed-root ownership list, rather than a separate packaging fixture.
import fs from 'node:fs';
import {fileURLToPath} from 'node:url';
import {inspectZip,validatePackage,verifyHash} from '../gpt-niang-usage/runtime/update.mjs';
const root=new URL('../',import.meta.url);
const version=JSON.parse(fs.readFileSync(new URL('gpt-niang-usage/package.json',root),'utf8')).version;
const filename='gpt-niang-usage-widget-v'+version+'-windows.zip';
const bytes=fs.readFileSync(process.argv[2]??fileURLToPath(new URL('dist/'+filename,root)));
const zip=inspectZip(bytes);
const packagedVersion=process.argv[2]?JSON.parse(zip.files.get('gpt-niang-usage/package.json').toString('utf8')).version:version;
validatePackage(zip,packagedVersion);
const helper=fs.readFileSync(new URL('gpt-niang-usage/runtime/update-helper.ps1',root),'utf8');
const block=helper.match(/\$managed=@\(([\s\S]*?)\)/)?.[1];
if(!block)throw new Error('Updater managed-root declaration not found');
const managed=new Set([...block.matchAll(/'([^']+)'/g)].map(match=>match[1]));
const conflicts=[...new Set([...zip.files.keys()].map(name=>name.split('/')[0]))].filter(name=>!managed.has(name));
if(conflicts.length)throw new Error('Package collides with unmanaged installation roots: '+conflicts.join(', '));
if(!process.argv[2])verifyHash(bytes,fs.readFileSync(new URL('dist/SHA256SUMS.txt',root)),{name:filename,size:bytes.length});
console.log('PASS: release package, checksum and updater managed-root compatibility ('+version+')');
