import { readFile, readdir, writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const read = (relative) => readFile(path.join(root, relative), 'utf8');
try {
  await read('_context/MANAGEMENT-MODEL.yaml');
  throw new Error('Explicit management model found: resolve its profile and backend before using this classic/Markdown generator.');
} catch (error) { if (error.code !== 'ENOENT') throw error; }

const rows = (text) => text.split(/\r?\n/).filter(line => line.startsWith('|')).map(line => line.split('|').slice(1, -1).map(cell => cell.trim()));
const ids = (text) => [...new Set(text.match(/\b(?:OBJ|REQ|FR|NFR|AC|ADR|TEST)-\d{3}\b/g) ?? [])];
const entities = new Map();
const add = (id, type, description, parent, source) => {
  if (entities.has(id)) throw new Error(`Duplicate definition: ${id}`);
  entities.set(id, { id, type, description, parent, source, decisions: [], workPackages: [], tests: [] });
};
const vsd = await read('_context/VSD.md');
if (!vsd.includes('| Repository Type | Software Product |')) throw new Error('This generator requires Software Product scope.');
for (const row of rows(vsd)) if (/^OBJ-\d{3}$/.test(row[0])) add(row[0], 'Objective', row[1], [], '_context/VSD.md');
for (const row of rows(await read('_context/_specification/BRD.md'))) if (/^REQ-\d{3}$/.test(row[0])) add(row[0], 'Requirement', row[1], ids(row[3]), '_context/_specification/BRD.md');
const specificationSources = ['_context/_specification/NFRD.md', ...(await readdir(path.join(root, '_context/_specification/FRDs'))).filter(name => name.endsWith('.md')).sort().map(name => `_context/_specification/FRDs/${name}`)];
for (const source of specificationSources) {
  for (const row of rows(await read(source))) {
    if (/^(?:FR|NFR)-\d{3}$/.test(row[0])) add(row[0], row[0].startsWith('NFR') ? 'Quality Requirement' : 'Functional Requirement', row[1], ids(row[3]), source);
    if (/^AC-\d{3}$/.test(row[0])) add(row[0], 'Acceptance Criterion', `Given ${row[1]}; When ${row[2]}; Then ${row[3]}`, ids(row[4]), source);
  }
}
const dangling = [];
const orphans = [];
for (const entity of entities.values()) {
  if (entity.type !== 'Objective' && !entity.parent.length) orphans.push(entity.id);
  for (const parent of entity.parent) if (!entities.has(parent)) dangling.push(`${entity.id} → ${parent}`);
}
const addText = await read('_context/_design/ADD.md');
const decisionDefinitions = new Set(rows(addText.split('## 10. Requirements Addressed')[0]).filter(row => /^ADR-\d{3}$/.test(row[0])).map(row => row[0]));
for (const row of rows(addText.split('## 10. Requirements Addressed')[1] ?? '')) {
  if (!/^ADR-\d{3}$/.test(row[0])) continue;
  if (!decisionDefinitions.has(row[0])) dangling.push(`Missing decision: ${row[0]}`);
  for (const requirement of ids(row[1])) {
    if (entities.has(requirement)) entities.get(requirement).decisions.push(row[0]);
    else dangling.push(`${row[0]} → ${requirement}`);
  }
}
const tests = [];
// ADR-007 is explicitly superseded by ADR-011 in ADD; retain its definition as history.
for (const entity of entities.values()) entity.decisions = entity.decisions.filter(id => id !== 'ADR-007');
const planningFiles = (await readdir(path.join(root, '_context/_planning'))).filter(name => /^(?:INI|PRJ|WP)-\d{3}\.md$/.test(name)).sort();
const planningTexts = new Map(await Promise.all(planningFiles.map(async name => [name.slice(0, -3), await read('_context/_planning/' + name)])));
const roadmap = await read('_context/_time/ROADMAP.md');
const horizons = new Set(rows(roadmap).filter(row => /^HOR-\d{3}$/.test(row[0])).map(row => row[0]));
const milestones = new Map(rows(roadmap).filter(row => /^MS-\d{3}$/.test(row[0])).map(row => [row[0], row]));
const hierarchyOrphans = [];
const tasks = new Set();
for (const [id, text] of planningTexts) {
  if (id.startsWith('INI-')) {
    const relations = rows(text.split('## 2. Serves Objective(s)')[1]?.split('## 3.')[0] ?? '').filter(row => /^OBJ-\d{3}$/.test(row[0]));
    if (!relations.length) hierarchyOrphans.push(id);
    for (const row of relations) if (!entities.has(row[0])) dangling.push(id + ' → ' + row[0]);
  }
  if (id.startsWith('PRJ-')) {
    const parents = rows(text.split('## 2. Belongs to Initiative')[1]?.split('## 3.')[0] ?? '').filter(row => /^INI-\d{3}$/.test(row[0]));
    if (!parents.length) hierarchyOrphans.push(id);
    for (const row of parents) if (!planningTexts.has(row[0])) dangling.push(id + ' → ' + row[0]);
    for (const row of rows(text.split('## 3. Target Milestone')[1]?.split('## 4.')[0] ?? '')) {
      if (!/^MS-\d{3}$/.test(row[0])) continue;
      if (!milestones.has(row[0])) dangling.push(id + ' → ' + row[0]);
      if (!horizons.has(row[1])) dangling.push(id + ' → ' + row[1]);
      if (milestones.has(row[0]) && milestones.get(row[0])[2] !== row[1]) dangling.push(id + ': milestone/horizon mismatch');
    }
  }
  for (const row of rows(text.split('## 4. Tasks')[1]?.split('## 5.')[0] ?? '')) {
    if (!/^TSK-\d{3}$/.test(row[0])) continue;
    if (tasks.has(row[0])) throw new Error('Duplicate task: ' + row[0]);
    tasks.add(row[0]);
  }
}
for (const [id, row] of milestones) if (!horizons.has(row[2])) dangling.push(id + ' → ' + row[2]);
const planningOrphans = [];
const workPackages = [];
try {
  const wpDirectory = '_context/_planning';
  for (const name of (await readdir(path.join(root, wpDirectory))).filter(name => /^WP-\d{3}\.md$/.test(name)).sort()) {
    const text = await read(`${wpDirectory}/${name}`);
    const wpId = rows(text).find(row => row[0] === 'Work Package ID')?.[1];
    if (!/^WP-\d{3}$/.test(wpId ?? '')) throw new Error(`Missing WP identifier: ${name}`);
    const project = text.match(/## 2\. Belongs to Project[\s\S]*?\| (PRJ-\d{3}) \|/)?.[1];
    if (!project) planningOrphans.push(wpId);
    else await read(`_context/_planning/${project}.md`);
    const realized = rows(text.match(/## 3\. Realizes([\s\S]*?)## 4\. Tasks/)?.[1] ?? '').map(row => row[0]).filter(id => /^(?:FR|NFR)-\d{3}$/.test(id));
    if (!realized.length) planningOrphans.push(wpId);
    for (const requirement of realized) {
      if (entities.has(requirement)) entities.get(requirement).workPackages.push(wpId);
      else dangling.push(`${wpId} → ${requirement}`);
    }
    workPackages.push(wpId);
  }
} catch (error) { if (error.code !== 'ENOENT') throw error; }
for (const row of rows(await read('_context/_verification/TMP.md'))) {
  if (!/^(?:FR|NFR)-\d{3}$/.test(row[0]) || !/^TEST-\d{3}:/.test(row[1])) continue;
  const test = { id: row[1].match(/^TEST-\d{3}/)[0], requirement: row[0], evidence: row[2], plannedStatus: row[3] };
  tests.push(test);
  if (entities.has(test.requirement)) entities.get(test.requirement).tests.push(test);
  else dangling.push(`${test.id} → ${test.requirement}`);
}
if (new Set(tests.map(test => test.id)).size !== tests.length) throw new Error('Duplicate test IDs');
if (dangling.length || orphans.length || hierarchyOrphans.length || planningOrphans.length) throw new Error(`Source defects; route to owning specialist: ${JSON.stringify({ dangling, orphans, hierarchyOrphans, planningOrphans })}`);

const requirements = [...entities.values()].filter(entity => ['Functional Requirement', 'Quality Requirement'].includes(entity.type));
const untested = requirements.filter(entity => !entity.tests.length);
const unplanned = requirements.filter(entity => !entity.workPackages.length);
const unevidenced = tests.filter(test => !test.evidence || test.evidence === '—');
const evidencePath = (value) => value.replace(/\]\(\.\.\/\.\.\//g, '](../');
const evidenceFor = entity => [...new Set(entity.tests.filter(test => test.evidence && test.evidence !== '—').map(test => test.id + ': ' + evidencePath(test.evidence)))].join('; ') || '—';
const counts = Object.fromEntries(['Objective', 'Requirement', 'Functional Requirement', 'Quality Requirement', 'Acceptance Criterion'].map(type => [type, [...entities.values()].filter(entity => entity.type === type).length]));
const nfrWithoutEvidence = requirements.filter(entity => entity.type === 'Quality Requirement' && entity.tests.every(test => !test.evidence || test.evidence === '—'));
const previous = await read('_context/TRACEABILITY-MATRIX.md').catch(error => { if (error.code !== 'ENOENT') throw error; return ''; });
const previousIds = new Set(rows(previous).filter(row => /^(?:OBJ|REQ|FR|NFR|AC)-\d{3}$/.test(row[0])).map(row => row[0]));
const removed = [...previousIds].filter(id => !entities.has(id));
const added = [...entities.keys()].filter(id => !previousIds.has(id));
if (removed.length) throw new Error('Material row removal requires confirmation: ' + removed.join(', '));
for (const test of tests) {
  for (const match of test.evidence.matchAll(/\]\(([^)#]+)(?:#[^)]*)?\)/g)) {
    if (/^[a-z]+:/i.test(match[1])) continue;
    await readFile(path.resolve(root, '_context/_verification', match[1]));
  }
}
const date = new Date().toISOString();
const safe = (text) => String(text).replaceAll('|', '\\|').replaceAll('\n', ' ');
const table = [...entities.values()].sort((a, b) => {
  const order = { Objective: 0, Requirement: 1, 'Functional Requirement': 2, 'Quality Requirement': 3, 'Acceptance Criterion': 4 };
  return order[a.type] - order[b.type] || a.id.localeCompare(b.id);
}).map(entity => {
  const status = entity.tests.length ? `Plan: ${[...new Set(entity.tests.map(test => test.plannedStatus))].join(', ')}; full execution/acceptance unknown` : 'No direct execution record';
  return `| ${entity.id} | ${entity.type} | ${safe(entity.description)} | ${entity.parent.join(', ') || '—'} | ${entity.decisions.join(', ') || '—'} | ${entity.workPackages.join(', ') || '—'} | ${entity.tests.map(test => test.id).join(', ') || '—'} | ${safe(evidenceFor(entity))} | ${status} |`;
}).join('\n');
const output = `# Matriz de trazabilidad\n\n## Title\n\n| Field | Value |\n| --- | --- |\n| Document | Requirements Traceability Matrix |\n| Initiative | Portal de gestión de propiedades |\n| Version | 0.2 |\n| Status | Generated projection; not an approval |\n| Author | Vestigator |\n| Reviewers | Pendientes |\n| Organization | Aelium |\n| Last Updated | ${date} |\n\n## 1. Purpose\n\nProyección de fuentes locales. Sin MANAGEMENT-MODEL.yaml: classic + markdown; Repository Type Software Product. Specification, Design, Planning, Time y Verification definition se resuelven como Markdown. Verification execution es externa. Se proyectan las referencias locales parciales explícitamente vinculadas por TMP y se comprueba su disponibilidad; no se consulta un ejecutor remoto ni se convierte esta matriz en autoridad de resultados. Los informes locales por runId no garantizan inmutabilidad. El estado Not Run se presenta como declaración del plan, no como estado obtenido de un ejecutor. No se crea ni migra configuración.\n\nFuentes: VSD, BRD, NFRD, ${specificationSources.length - 1} FRDs, ADD y TMP. Planning contiene ${planningFiles.filter(name => name.startsWith('INI-')).length} iniciativas, ${planningFiles.filter(name => name.startsWith('PRJ-')).length} proyectos, ${workPackages.length} Work Packages y ${tasks.size} tareas; Time contiene Roadmap con ${horizons.size} horizontes y ${milestones.size} hitos sin fechas comprometidas. La gestión individual y base técnica fueron confirmadas el 2026-10-03. Política y estrategia de Aelium se provisionaron desde CRM por instrucción del usuario; conservan su estado Draft. El stack de ADR-005 a ADR-007 fue aceptado el 2026-10-03; los detalles de negocio y ADR-008 siguen pendientes. Los borradores no se convierten en decisiones aprobadas mediante esta matriz.\n\n## 2. ID Prefix Registry\n\n| Semantic entity | Classic | Dimension |\n| --- | --- | --- |\n| Objective | OBJ | Specification |\n| Requirement | REQ | Specification |\n| Functional Requirement | FR | Specification |\n| Quality Requirement | NFR | Specification |\n| Acceptance Criterion | AC | Specification |\n| Architecture Decision | ADR | Design |\n| Initiative / Project / Work Package / Task | INI / PRJ / WP / TSK | Planning |\n| Roadmap / Horizon / Milestone | RDM / HOR / MS | Time |\n| Test / Evidence | TEST / EVD | Verification |\n\n## 3. Matrix\n\n${entities.size} filas: ${counts.Objective} OBJ, ${counts.Requirement} REQ, ${counts['Functional Requirement']} FR, ${counts['Quality Requirement']} NFR y ${counts['Acceptance Criterion']} AC. Las relaciones de decisión y prueba se enlazan solo donde la fuente las declara; no se propagan de padre a hijo. Una celda vacía en un criterio no significa que el requisito padre carezca de prueba.\n\n| ID | Type | Description | Parent | Addressed by (decision) | Realized by (work package) | Verified by (test) | Evidence | Status |\n| --- | --- | --- | --- | --- | --- | --- | --- | --- |\n${table}\n\n## 4. Gap Checklist\n\n| # | Check | Findings |\n| --- | --- | --- |\n| 1 | Requirement with no implementation | ${unplanned.length} FR/NFR sin Work Package (FR-010 y FR-011, fase futura). Significa falta de relación de planificación, no una inspección de código |\n| 2 | Requirement with no test | ${untested.length}: ${untested.map(entity => entity.id).join(', ')}; fase futura Ibercaja/n8n |\n| 3 | Orphan task | ${planningOrphans.length} Work Packages huérfanos detectados; ${workPackages.length} paquetes con proyecto y requisitos |\n| 4 | Requirement modified after verification | No concluyente: informes locales de actualización del 2026-10-11 y revisión documental del 2026-10-16; Last Updated no identifica por sí solo una modificación semántica posterior del requisito. Falta control de versiones/hashes por variante para evaluar vigencia |\n| 5 | NFR with no evidence | ${nfrWithoutEvidence.length} NFR sin enlace directo de evidencia en las filas del TMP; ${nfrWithoutEvidence.map(entity => entity.id).join(', ')}. Ningún NFR se declara aceptado por los enlaces parciales |\n| 6 | Work closed but requirement still open | Ningún Work Package de producto se declara cerrado; tareas de infraestructura terminadas no verifican requisitos de aplicación |\n\nCategorías separadas: 0 referencias colgantes en relaciones extraídas; 0 entidades huérfanas; ${unplanned.length} requisitos sin realización por WP; ${untested.length} requisitos sin prueba; ${unevidenced.length} pruebas sin enlace de evidencia en su fila principal del TMP (no niega evidencia narrativa anterior de aplicación); 0 pruebas huérfanas. La evidencia de las 16 familias del actualizador es parcial y no acredita cierre. ADR-007 se conserva como antecedente en ADD y no se proyecta como decisión activa, sustituida por ADR-011. Los criterios de aceptación se vinculan explícitamente a FR/NFR; no se fabrican enlaces directos a pruebas desde menciones narrativas. La aprobación, vigencia organizativa y conformidad de templates no han sido auditadas por este generador.\n\n## References\n\n- [VSD](VSD.md), [BRD](_specification/BRD.md), [NFRD](_specification/NFRD.md).\n- [ADD](_design/ADD.md), [TMP](_verification/TMP.md), [SQCA](_verification/SQCA.md).\n- [Actualizaciones PRJ-003](_planning/PRJ-003.md), [entorno WP-010](_planning/WP-010.md), [Roadmap](_time/ROADMAP.md).\n- La evidencia enlazada conserva los límites descritos por Quaestor en TMP; los enlaces locales no acreditan procedencia ni integridad por sí solos.\n- Generador: [_generated/generate-traceability-matrix.mjs](_generated/generate-traceability-matrix.mjs). Su soporte es deliberadamente classic + Markdown con relaciones directas de Work Packages. Comprueba jerarquía y enlaces locales. No audita capacidad ni integridad de artefactos y no ejecuta pruebas.\n`;
if (process.argv.includes('--check')) {
  console.log(JSON.stringify({mode:'Refresh preview',rows:entities.size,counts,added,removed,tests:tests.length,tasks:tasks.size,dangling,orphans,planningOrphans,hierarchyOrphans,withoutWorkPackage:unplanned.map(e=>e.id),withoutTest:untested.map(e=>e.id),withoutEvidence:unevidenced.length},null,2));
  process.exit(0);
}
await mkdir(path.join(root, '_context'), { recursive: true });
await writeFile(path.join(root, '_context/TRACEABILITY-MATRIX.md'), output, 'utf8');
console.log(JSON.stringify({ generatedAt: date, rows: entities.size, decisions: decisionDefinitions.size, tests: tests.length, dangling: dangling.length, orphans: orphans.length, withoutWorkPackage: unplanned.length, workPackages: workPackages.length, withoutTest: untested.map(entity => entity.id), withoutEvidence: unevidenced.length }, null, 2));
