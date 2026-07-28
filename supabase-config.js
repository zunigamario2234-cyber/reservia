// Credenciales de Supabase, en un solo lugar.
//
// Hasta acá la URL y la anon key estaban copiadas a mano en los 7 HTML y en
// api/_lib/resend.js. El proyecto no tiene build step, así que no hay forma de
// sustituirlas por entorno: el archivo compartido es la única manera de que
// exista un solo lugar donde cambiarlas.
//
// POR AHORA NO ELIGE ENTORNO. Este archivo define las credenciales de
// producción y nada más, a propósito: el objetivo de este paso es que el
// comportamiento quede idéntico al de antes en todos los hosts, para poder
// verificarlo contra producción. La selección por hostname (dominio real ->
// base real, cualquier otro host -> staging) se agrega cuando el proyecto de
// staging exista, en su propio commit. Mezclar las dos cosas haría imposible
// saber cuál de las dos rompió si algo falla.
//
// Que la anon key esté a la vista no es un descuido: es pública por diseño y
// va embebida en toda página que hable con Supabase. Lo que protege los datos
// es RLS, no la clave. La service_role key, esa sí secreta, NO va acá — vive
// solo en las env vars del servidor y la usa api/.
//
// CÓMO SE CONSUME
// Va en el <head>, después del SDK de Supabase y antes del <script> inline de
// la página. Es un script clásico sin defer, así que se ejecuta en orden y las
// constantes existen cuando el inline las usa.
//
// Define solo las credenciales, no el cliente: así no depende de que el SDK
// esté cargado, y cada página crea su cliente como necesite (app.html crea
// dos, uno de ellos con storageKey propio para las invitaciones).
//
// SI ESTE ARCHIVO NO CARGA
// El <script> inline de cada página muere en la primera línea que use las
// credenciales, y como las declaraciones de función se hoistean, la página
// queda viva pero inservible: se ve entera, congelada en "Cargando...", y los
// botones fallan en silencio. Por eso cada página lleva una guarda que corta
// antes y muestra un mensaje. Si tocas este archivo, no le cambies el nombre a
// las constantes sin actualizar las guardas.

const SUPABASE_URL = 'https://dqoqykngmtxtvbokxbzp.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRxb3F5a25nbXR4dHZib2t4YnpwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI0MTc1NDEsImV4cCI6MjA5Nzk5MzU0MX0.aLjslOdIod_wsdiHN3O7SRlbsM4hOj3nNQTlNTc_rY4';
