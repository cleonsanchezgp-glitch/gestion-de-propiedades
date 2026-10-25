# Pruebas del proyecto

El proyecto conserva las pruebas unitarias, de infraestructura local, de API,
frontend y del instalador nuevo de Windows. Las pruebas de los actualizadores
experimentales se retiraron con esas herramientas.

## Comandos principales

```powershell
npm test
npm run test:windows-installer
npm run backend:test
```

Las pruebas de integración usan la infraestructura Compose definida en
`tests/compose.yaml` y se preparan con `npm run test:prepare`. Las pruebas de
navegador del frontend se ejecutan con `npm run test:browser` cuando está
disponible el navegador de Playwright.

Los resultados temporales se guardan en `tests/artifacts/` y no forman parte de
la entrega al cliente.
