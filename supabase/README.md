# Base de datos en Supabase

La web (`index.html`) guarda el último listado de cheques en Supabase. Los usuarios ven la información después de iniciar sesión, y solo los administradores pueden cargar listados arrastrando el Excel.

## Configuración (una sola vez)

1. **Crear las tablas.** En Supabase, abrí SQL Editor → New query, pegá todo el contenido de `setup.sql` y tocá Run.
2. **Cerrar el registro público.** En Authentication → Sign In / Providers → Email, desactivá *Allow new users to sign up*.
   Los usuarios se crean a mano en Authentication → Users → Add user → Create new user, con *Auto Confirm User* tildado.
3. **Indicar la URL del sitio.** En Authentication → URL Configuration, cargá `https://pagos.tacoma-maderas.com.ar` en *Site URL*.
   Así funciona el link de "Olvidé mi contraseña".
4. **Copiar las claves.** En Project Settings → API Keys, copiá la *Publishable key* (o la *anon* legacy) y la URL del proyecto.
   Pegalas en `index.html`, en las constantes `SUPABASE_URL` y `SUPABASE_KEY`.
   Esa clave es pública por diseño: la seguridad la dan el login y las políticas RLS.

## Administradores

Solo los emails de la tabla `admins` pueden subir listados. Para sumar uno nuevo, corré esto en el SQL Editor:

```sql
insert into public.admins (email) values ('nuevo@tacoma-maderas.com.ar');
```

## Cómo se guardan los datos

- `cheques` tiene el último listado de cada empresa emisora; la empresa sale del pie del Excel del banco.
  Cada carga reemplaza completo el listado de esa empresa.
- `cargas` registra quién subió cada archivo y cuándo.
