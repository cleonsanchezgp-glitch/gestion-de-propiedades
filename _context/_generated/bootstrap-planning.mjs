import { mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const root = fileURLToPath(new URL('../../', import.meta.url));
const header = (document, field, id, status = 'Planned') => `## Title\n\n| Field | Value |\n| --- | --- |\n| Document | ${document} |\n| ${field} | ${id} |\n| Version | 0.1 |\n| Status | ${status} |\n| Author | Rector |\n| Reviewers | Responsable individual; identidad pendiente |\n| Organization | Aelium |\n| Last Updated | 2026-10-03 |\n`;
const status = (state) => `## Status\n\n| Field | Value |\n| --- | --- |\n| Overall status | ${state} |\n| Start date | ${state === 'In progress' ? '2026-10-03' : 'Pendiente'} |\n| Target completion | Pendiente de disponibilidad real; no fecha comprometida |\n`;
const write = async (file, content) => {
  const target = path.join(root, file);
  await mkdir(path.dirname(target), { recursive: true });
  await writeFile(target, content, { flag: 'wx' });
};
const work = [
  { id: 'WP-001', project: 'PRJ-002', name: 'Infraestructura de pruebas', state: 'In progress', reqs: ['NFR-001','NFR-003','NFR-004','NFR-005','NFR-006'], tasks: [
    ['TSK-001','Crear Compose aislado, realm y fixtures sintéticos','Done'],
    ['TSK-002','Implementar runner y pruebas negativas de infraestructura','Done'],
    ['TSK-003','Ejecutar comprobaciones de PostgreSQL y Keycloak y guardar resultado','In progress'],
    ['TSK-004','Añadir integración de API y navegador cuando exista el portal','Planned']
  ] },
  { id: 'WP-002', project: 'PRJ-001', name: 'Backend y persistencia', state: 'Planned', reqs: ['FR-001','FR-002','FR-003','FR-004','FR-005','NFR-003','NFR-006'], tasks: [
    ['TSK-005','Resolver conservación histórica, parciales y reglas de baja antes de cerrar esquema','Planned'],
    ['TSK-006','Crear backend Rust/Axum, migraciones SQL y repositorios','Planned'],
    ['TSK-007','Implementar consultas, validaciones, estados y resúmenes','Planned'],
    ['TSK-008','Implementar importación con reporte y validar discrepancias','Planned']
  ] },
  { id: 'WP-003', project: 'PRJ-001', name: 'Identidad y autorización', state: 'Planned', reqs: ['FR-007','NFR-004','NFR-005'], tasks: [
    ['TSK-009','Definir permisos por operación y usuarios autorizados','Planned'],
    ['TSK-010','Integrar cliente Keycloak PKCE y validación en backend','Planned'],
    ['TSK-011','Verificar acceso negativo, cierre y transporte de publicación','Planned']
  ] },
  { id: 'WP-004', project: 'PRJ-001', name: 'Frontend adaptable', state: 'Planned', reqs: ['FR-008','FR-009','NFR-001','NFR-002'], tasks: [
    ['TSK-012','Modularizar frontend con Vite y conectar contrato de API','Planned'],
    ['TSK-013','Crear diseño inmobiliario de Zaragoza para ambos formatos','Planned'],
    ['TSK-014','Verificar flujos con navegadores acordados y revisión visual','Planned']
  ] },
  { id: 'WP-005', project: 'PRJ-001', name: 'Documentos y recibos', state: 'Planned; scope confirmation pending', reqs: ['FR-006'], tasks: [
    ['TSK-015','Confirmar módulo, tipos, límites y conservación de adjuntos','Planned'],
    ['TSK-016','Implementar almacenamiento privado y descarga autorizada','Planned'],
    ['TSK-017','Verificar asociaciones, importación y acceso a recibos','Planned']
  ] }
];
for (const wp of work) await write(`_context/_planning/${wp.id}.md`, `${header(wp.name,'Work Package ID',wp.id,wp.state)}\n## 1. Overview\n\n${wp.name}. Realiza los requisitos indicados sin declarar que ya están satisfechos. Se trabaja en secuencia por un responsable individual; capacidad semanal desconocida.\n\n## 2. Belongs to Project\n\n| Project (PRJ-xxx) |\n| --- |\n| ${wp.project} |\n\n## 3. Realizes\n\n| Requirement (FR-xxx / NFR-xxx) | Notes |\n| --- | --- |\n${wp.reqs.map(id=>`| ${id} | Cobertura prevista; revisar decisiones pendientes antes de implementar |`).join('\n')}\n\n## 4. Tasks\n\n| ID | Task | Status | Owner |\n| --- | --- | --- | --- |\n${wp.tasks.map(t=>`| ${t[0]} | ${t[1]} | ${t[2]} | Responsable individual / Codex como colaborador técnico |`).join('\n')}\n\n## 5. ${status(wp.state).replace('## Status','Status')}\n## References\n\n- [BRD](../_specification/BRD.md), [NFRD](../_specification/NFRD.md), [ADD](../_design/ADD.md), [TMP](../_verification/TMP.md).\n`);
for (const [id, ini, name, ms, hor] of [['PRJ-001','INI-001','Portal de gestión','MS-001','HOR-001'],['PRJ-002','INI-002','Entorno reproducible de pruebas','MS-002','HOR-002']]) {
  const members = work.filter(w=>w.project===id);
  await write(`_context/_planning/${id}.md`, `${header(name,'Project ID',id,id==='PRJ-002'?'In progress':'Planned')}\n## 1. Overview\n\n${name}. Base técnica aceptada por el usuario el 2026-10-03; pendientes de producto explícitos en los Work Packages.\n\n## 2. Belongs to Initiative\n\n| Initiative (INI-xxx) |\n| --- |\n| ${ini} |\n\n## 3. Target Milestone\n\n| Milestone (MS-xxx) | Horizon |\n| --- | --- |\n| ${ms} | ${hor} |\n\n## 4. Scope\n\n### In Scope\n\n${id==='PRJ-001'?'Backend, frontend adaptable, Keycloak y migración revisable; módulos condicionados al alcance documentado.':'Compose, realm aislado, fixtures sintéticos y runner con artefactos; pruebas de aplicación cuando exista código.'}\n\n### Out of Scope\n\nAutomatización bancaria y publicación remota. No se promete capacidad, fechas ni resultado de pruebas aún no ejecutadas.\n\n## 5. Work Packages\n\n| ID (WP-xxx) | Work Package | Status |\n| --- | --- | --- |\n${members.map(w=>`| ${w.id} | ${w.name} | ${w.state} |`).join('\n')}\n\n## 6. ${status(id==='PRJ-002'?'In progress':'Planned').replace('## Status','Status')}\n## References\n\n- [VSD](../VSD.md), [ADD](../_design/ADD.md), [Roadmap](../_time/ROADMAP.md).\n`);
}
for (const [id,name,obj,prj] of [['INI-001','Entrega del portal','OBJ-001, OBJ-002, OBJ-003','PRJ-001'],['INI-002','Infraestructura de verificación','OBJ-001, OBJ-003','PRJ-002']]) await write(`_context/_planning/${id}.md`, `${header(name,'Initiative ID',id)}\n## 1. Overview\n\n${name}. Gestión individual confirmada por el usuario; planificación local Markdown en ausencia de otra autoridad declarada. Dos iniciativas: la infraestructura tiene trabajo propio de aprovisionamiento, datos y ejecución y puede verificarse antes de la aplicación. El usuario ha autorizado implementarla; no se presume infraestructura comercial ni capacidad adicional.\n\n## 2. Serves Objective(s)\n\n| Objective (OBJ-xxx) | How this Initiative serves it |\n| --- | --- |\n${obj.split(', ').map(o=>`| ${o} | ${id==='INI-001'?'Entregar la capacidad descrita en VSD':'Proporcionar verificación reproducible de centralización y acceso'} |`).join('\n')}\n\n## 3. Projects\n\n| ID (PRJ-xxx) | Project | Status |\n| --- | --- | --- |\n| ${prj} | ${name} | ${id==='INI-002'?'In progress':'Planned'} |\n\n## 4. ${status(id==='INI-002'?'In progress':'Planned').replace('## Status','Status')}\n## References\n\n- [VSD](../VSD.md).\n`);
await write('_context/_time/ROADMAP.md', `${header('Roadmap','Roadmap ID','RDM-001','Draft - dates pending')}\n## 1. Purpose\n\nOrden de estados objetivo sin inventar fechas. Un responsable individual gestiona la entrega; disponibilidad y esfuerzo no confirmados. La infraestructura se gestiona como iniciativa independiente. Este documento no compromete plazos y no contiene Tasks.\n\n## 2. Horizons\n\n| Horizon | Period | Theme |\n| --- | --- | --- |\n| HOR-001 | Pendiente de capacidad | Primera fase del portal |\n| HOR-002 | Inicio de infraestructura 2026-10-03; cierre pendiente | Verificación reproducible |\n\n## 3. Milestones\n\n| ID | Milestone | Horizon | Target Date | Status |\n| --- | --- | --- | --- | --- |\n| MS-001 | Portal validado con criterios acordados | HOR-001 | Sin fecha comprometida | Planned |\n| MS-002 | Infraestructura reproducible con evidencia de comprobación | HOR-002 | Sin fecha comprometida | In progress |\n\n## References\n\n- [Portal](../_planning/PRJ-001.md), [infraestructura](../_planning/PRJ-002.md).\n`);
console.log('Created 2 initiatives, 2 projects, 5 work packages and roadmap; no delivery dates invented.');
