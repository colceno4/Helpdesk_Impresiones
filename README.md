# Prorrateo de Impresión — App consolidada

Aplicación de una sola página (`index.html`, sin build ni dependencias de servidor)
para prorratear impresiones Ricoh por Centro de Costo, con historial, detección de
usuarios sin CeCo y consumo por empresa. Persiste en Supabase.

## Estructura del proyecto

```
.
├── index.html          # Toda la app (HTML + CSS + JS en un solo archivo)
├── vercel.json          # Config de despliegue estático en Vercel
├── supabase/
│   └── schema.sql       # Esquema completo de la base de datos (tablas, RPCs, políticas)
└── README.md
```

## 1) Subir a GitHub

```bash
git init
git add .
git commit -m "App consolidada de prorrateo de impresiones"
git branch -M main
git remote add origin https://github.com/<tu-usuario>/<tu-repo>.git
git push -u origin main
```

## 2) Crear el proyecto en Supabase

1. Entra a https://supabase.com/dashboard → **New project**.
2. Una vez creado, ve a **SQL Editor** → **New query**, pega todo el contenido de
   `supabase/schema.sql` y ejecútalo (`Run`). Esto crea las tablas
   (`printer_records`, `printer_batches`, `ceco_users`, etc.), las funciones RPC
   (`usuarios_sin_ceco`, `informe_por_empresa`, `empresa_from_ceco`) y las políticas
   de acceso.
3. Ve a **Project Settings → API** y copia:
   - **Project URL**
   - **anon / public key**

   Estos dos valores son los que la app pide la primera vez que la abres (botón ⚙
   arriba a la derecha). Se guardan en el `localStorage` del navegador, **no** se
   suben al repositorio ni quedan expuestos en el código — cada persona que use la
   app los configura una sola vez desde el navegador.

   Alternativa: si prefieres que la app abra ya conectada sin pedir configuración,
   puedes fijar esos dos valores directamente en `index.html`, en la constante
   `SUPABASE_CONFIG_DEFAULT` (línea ~782). Ten en cuenta que quedarían visibles en
   el repositorio si lo subes público; la anon key está pensada para ser pública
   (el acceso real lo controlan las políticas RLS de Supabase), pero si prefieres
   no exponerla igual, deja el método del paso 3 (localStorage).

## 3) Desplegar en Vercel

1. Entra a https://vercel.com/new e importa el repositorio de GitHub que acabas
   de crear.
2. Framework Preset: **Other** (es un sitio estático, no requiere build ni
   variables de entorno).
3. Deploy. Vercel servirá `index.html` directamente.
4. Abre la URL que te da Vercel, pulsa el botón ⚙ (arriba a la derecha) e ingresa
   la Project URL y la anon key de Supabase del paso anterior.

## Actualizar la app más adelante

Como todo vive en `index.html`, para hacer cambios:

```bash
# edita index.html con cualquier editor
git add index.html
git commit -m "Ajuste en la app"
git push
```

Vercel vuelve a desplegar automáticamente con cada push a `main`.

Si agregas nuevas tablas o funciones a Supabase, súmalas también al final de
`supabase/schema.sql` para mantener un registro de todo el esquema.
