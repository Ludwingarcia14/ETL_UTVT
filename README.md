# Proyecto ETL UTVT — Carga de Ventas

Proceso ETL desarrollado en **SQL Server Integration Services (SSIS)** con Visual Studio, que carga y transforma información de clientes, productos y ventas desde archivos CSV hacia un Data Warehouse dimensional (`DWUTVTVentas`), aplicando validaciones, deduplicación, registro de errores y bitácora de proceso.

## Tabla de contenidos

- [Arquitectura](#arquitectura)
- [Requisitos](#requisitos)
- [Estructura del repositorio](#estructura-del-repositorio)
- [Base de datos](#base-de-datos)
- [Flujo del paquete](#flujo-del-paquete)
- [Reglas de validación](#reglas-de-validación)
- [Registro de errores y proceso](#registro-de-errores-y-proceso)
- [Cómo ejecutar](#cómo-ejecutar)
- [Cómo re-probar desde cero](#cómo-re-probar-desde-cero)
- [Resultados esperados](#resultados-esperados)
- [Notas de diseño](#notas-de-diseño)

## Arquitectura

El proceso sigue un patrón ETL dimensional:

1. **Extracción**: lectura de 3 archivos CSV (`Clientes.csv`, `Productos.csv`, `Ventas.csv`) con codificación Windows-1252.
2. **Transformación**: limpieza (UPPER/TRIM), deduplicación por identificador de origen, conversión de tipos, validaciones de negocio y cálculo de métricas.
3. **Carga**: inserción en tablas de dimensión (`DimCliente`, `DimProducto`) y hechos (`FactVentas`), con búsqueda de claves subrogadas (surrogate keys) vía Lookup.

Un único paquete (`CargaVentas.dtsx`) orquesta todo el flujo mediante un Control Flow con contenedor de secuencia.

## Requisitos

- SQL Server 2017 o superior (probado en SQL Server 17, `localhost`)
- SQL Server Management Studio (SSMS)
- Visual Studio con la extensión **SQL Server Integration Services Projects**
- Proveedor **Microsoft OLE DB Driver for SQL Server** (no el Native Client antiguo)
- PowerShell (para el paso de compresión de archivos procesados)

## Estructura del repositorio

```
Proyecto_ETL_UTVT/
├── data/
│   ├── entrada/        # CSV de entrada (codificación 1252)
│   └── respaldo/       # Copia de respaldo de los CSV originales
├── ssis/
│   └── comprimir.ps1   # Script de compresión de archivos procesados
├── Proyecto_ETL_UTVT/
│   ├── CargaVentas.dtsx        # Paquete SSIS principal
│   ├── Project.params          # Parámetros del proyecto
│   ├── Proyecto_ETL_UTVT.dtproj
│   └── Proyecto_ETL_UTVT.database
├── Proyecto_ETL_UTVT.slnx      # Solución de Visual Studio
├── .gitignore
└── README.md
```

## Base de datos

La base `DWUTVTVentas` contiene:

| Objeto | Tipo | Descripción |
|--------|------|-------------|
| `DimCliente` | Dimensión | Clientes válidos con clave subrogada `IdClienteSK` |
| `DimProducto` | Dimensión | Productos válidos con clave subrogada `IdProductoSK` |
| `FactVentas` | Hechos | Ventas con métricas calculadas (Subtotal, IVA, Total) |
| `LogErrores` | Bitácora | Filas rechazadas con motivo, flujo y archivo de origen |
| `LogProceso` | Bitácora | Registro de cada ejecución con conteos y estatus |
| `CategoriaValida` | Catálogo | Categorías autorizadas para productos |

Las tablas de dimensión y hechos tienen **índices únicos** sobre las columnas de origen (`IdClienteOrigen`, `IdProductoOrigen`, `IdVentaOrigen`), lo que otorga **idempotencia**: re-ejecutar el paquete no genera duplicados.

### Procedimientos almacenados

- `usp_LogProceso_Inicio` — registra el inicio de la ejecución y devuelve el `IdProceso`.
- `usp_LogProceso_Fin` — actualiza la fila en proceso con los conteos finales y el estatus (`EXITOSO` / `COMPLETADO CON ERRORES`).
- `usp_LogError_Insert` — inserta registros de error.

## Flujo del paquete

### Control Flow

```
Registrar inicio (usp_LogProceso_Inicio)
   → Validar existencia de archivos (Script Task C#)
   → [Contenedor "Cargas"]
        DFT_Clientes → DFT_Productos → DFT_Ventas
   → Registrar estadísticas (usp_LogProceso_Fin)
   → Mover archivos procesados (Clientes, Productos, Ventas)
   → Comprimir archivos (Execute Process Task → PowerShell)
```

### Data Flows

Cada flujo sigue el patrón: **Flat File Source → Row Count (leídos) → Sort (dedup) → Derived Column (limpieza) → Data Conversion → Conditional Split (validaciones) → [Lookups] → Row Count (insertados) → OLE DB Destination**. Las filas rechazadas se derivan a `LogErrores` mediante ramas de error unificadas con Union All.

- **DFT_Clientes**: limpieza de texto, validación de campos obligatorios y estado activo.
- **DFT_Productos**: validación de precio, costo, estado, categoría, más Lookup contra `CategoriaValida`.
- **DFT_Ventas**: validación de cantidad y precio, Lookups de cliente y producto para obtener claves subrogadas, y cálculo de métricas (Subtotal, IVA 16%, Total).

## Reglas de validación

| Entidad | Rechazo | Motivo registrado |
|---------|---------|-------------------|
| Cliente | Nombre/Apellido/Id vacío | Cliente invalido |
| Cliente | Activo = 0 | Cliente inactivo |
| Producto | Precio ≤ 0 | Precio invalido |
| Producto | Costo ≤ 0 | Costo invalido |
| Producto | Activo = 0 | Producto inactivo |
| Producto | Categoría vacía | Sin categoria |
| Producto | Categoría no en catálogo | Categoria no autorizada |
| Venta | Cantidad ≤ 0 | Cantidad invalida |
| Venta | Precio unitario ≤ 0 | Precio invalido |
| Venta | Fecha no convertible | Fecha invalida |
| Venta | Cliente inexistente en dimensión | Cliente inexistente |
| Venta | Producto inexistente en dimensión | Producto inexistente |

## Registro de errores y proceso

- **LogErrores**: cada fila rechazada guarda el motivo (`DescripcionError`), el flujo (`NombreFlujo`), el archivo de origen (`ArchivoOrigen`), el paquete (`NombrePaquete`) y una referencia de la fila (`FilaOrigen`). Todos los textos se convierten a no-Unicode (código de página 1252) para coincidir con las columnas `VARCHAR` del destino.
- **LogProceso**: al finalizar, se registran `TotalLeidos`, `TotalInsertados`, `TotalErrores` y el estatus. Los conteos se obtienen mediante 9 componentes **Row Count** (3 por entidad) sumados por expresión, evitando que un flujo sobrescriba los conteos de otro.

## Cómo ejecutar

1. Restaurar/crear la base `DWUTVTVentas` con el script SQL incluido.
2. Abrir la solución en Visual Studio.
3. Verificar que el connection manager `cm_DWUTVTVentas` apunte a tu instancia de SQL Server.
4. Confirmar que las variables de ruta (`RutaEntrada`, `RutaProcesados`, `RutaErrores`) correspondan a tu entorno.
5. Ejecutar el paquete (F5).

## Cómo re-probar desde cero

```sql
DELETE FROM FactVentas;
DELETE FROM DimCliente;
DELETE FROM DimProducto;
DELETE FROM LogErrores;
DELETE FROM LogProceso;
```

Y restaurar los CSV de entrada desde el respaldo:

```powershell
copy data\respaldo\*.csv data\entrada\
```

## Resultados esperados

| Métrica | Valor |
|---------|-------|
| Clientes leídos → cargados | 1000 → 850 |
| Productos leídos → cargados | 500 → 395 |
| Ventas leídas → cargadas | 5000 → 3264 |
| Total leídos (crudos) | 6500 |
| Total insertados | 4509 |
| Total errores | 1663 |

La diferencia entre leídos y (insertados + errores) corresponde a los registros duplicados descartados en la fase de deduplicación.

## Notas de diseño

- **Codificación 1252**: los CSV se convirtieron a Windows-1252 para evitar conflictos Unicode/no-Unicode en las conversiones hacia columnas `VARCHAR`.
- **Categorías del enunciado vs. datos reales**: el catálogo `CategoriaValida` se construyó a partir de las categorías **realmente observadas** en los datos (ALIMENTOS, DEPORTES, ELECTRÓNICA, HOGAR, JUGUETES, OFICINA, ROPA, SALUD). Las categorías listadas en el enunciado del examen no existen en los insumos, por lo que la validación de "categoría no autorizada" produce 0 filas contra estos datos. Este comportamiento es intencional y documentado.
- **Conteo por primer match**: el Conditional Split deriva cada fila por la **primera** condición que cumple, por lo que un registro con múltiples defectos se registra una sola vez, con el motivo de mayor prioridad.
- **Row Count "leídos" antes de deduplicar**: los conteos de "leídos" reflejan las filas crudas del archivo (antes del Sort), de modo que `Leídos = Insertados + Errores + Duplicados`.
- **Idempotencia**: los índices únicos sobre las columnas de origen permiten re-ejecutar el paquete sin generar duplicados.
