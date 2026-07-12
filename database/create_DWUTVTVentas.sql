/*==============================================================================
  Base de datos: DWUTVTVentas (Data Warehouse de Ventas)
  Archivo:       create_DWUTVTVentas.sql
  Autor:         Octavio Duarte
  Fecha:         2026-07-03
==============================================================================*/

IF DB_ID('DWUTVTVentas') IS NULL
BEGIN
    CREATE DATABASE DWUTVTVentas;
END
GO

USE DWUTVTVentas;
GO

IF SCHEMA_ID('stg') IS NULL EXEC('CREATE SCHEMA stg');
GO

DROP TABLE IF EXISTS dbo.FactVentas;
DROP TABLE IF EXISTS dbo.DimProducto;
DROP TABLE IF EXISTS dbo.DimCliente;
DROP TABLE IF EXISTS dbo.LogErrores;
DROP TABLE IF EXISTS dbo.LogProceso;
DROP TABLE IF EXISTS stg.Clientes;
DROP TABLE IF EXISTS stg.Productos;
DROP TABLE IF EXISTS stg.Ventas;
GO

CREATE TABLE stg.Clientes (
    IdCliente      VARCHAR(50)  NULL,
    Nombre         VARCHAR(200) NULL,
    Apellido       VARCHAR(200) NULL,
    Correo         VARCHAR(200) NULL,
    Telefono       VARCHAR(50)  NULL,
    Ciudad         VARCHAR(200) NULL,
    Estado         VARCHAR(200) NULL,
    Pais           VARCHAR(200) NULL,
    Activo         VARCHAR(10)  NULL,
    FechaRegistro  VARCHAR(50)  NULL
);
GO

CREATE TABLE stg.Productos (
    IdProducto     VARCHAR(50)  NULL,
    NombreProducto VARCHAR(200) NULL,
    Categoria      VARCHAR(200) NULL,
    Precio         VARCHAR(50)  NULL,
    Costo          VARCHAR(50)  NULL,
    Activo         VARCHAR(10)  NULL
);
GO

CREATE TABLE stg.Ventas (
    IdVenta        VARCHAR(50)  NULL,
    IdCliente      VARCHAR(50)  NULL,
    IdProducto     VARCHAR(50)  NULL,
    Cantidad       VARCHAR(50)  NULL,
    PrecioUnitario VARCHAR(50)  NULL,
    FechaVenta     VARCHAR(50)  NULL,
    Sucursal       VARCHAR(200) NULL
);
GO

CREATE TABLE dbo.DimCliente (
    IdClienteSK      INT IDENTITY(1,1) NOT NULL,
    IdClienteOrigen  INT           NOT NULL,
    Nombre           VARCHAR(100)  NOT NULL,
    Apellido         VARCHAR(100)  NOT NULL,
    Correo           VARCHAR(150)  NULL,
    Telefono         VARCHAR(20)   NULL,
    Ciudad           VARCHAR(100)  NULL,
    Estado           VARCHAR(100)  NULL,
    Pais             VARCHAR(100)  NULL,
    FechaRegistro    DATE          NULL,
    FechaCarga       DATETIME      NOT NULL CONSTRAINT DF_DimCliente_FechaCarga DEFAULT (GETDATE()),
    CONSTRAINT PK_DimCliente PRIMARY KEY CLUSTERED (IdClienteSK)
);
GO
CREATE UNIQUE NONCLUSTERED INDEX UX_DimCliente_Origen
    ON dbo.DimCliente (IdClienteOrigen);
GO

CREATE TABLE dbo.DimProducto (
    IdProductoSK      INT IDENTITY(1,1) NOT NULL,
    IdProductoOrigen  INT            NOT NULL,
    NombreProducto    VARCHAR(150)   NOT NULL,
    Categoria         VARCHAR(100)   NOT NULL,
    Precio            DECIMAL(12,2)  NOT NULL,
    Costo             DECIMAL(12,2)  NOT NULL,
    FechaCarga        DATETIME       NOT NULL CONSTRAINT DF_DimProducto_FechaCarga DEFAULT (GETDATE()),
    CONSTRAINT PK_DimProducto PRIMARY KEY CLUSTERED (IdProductoSK)
);
GO
CREATE UNIQUE NONCLUSTERED INDEX UX_DimProducto_Origen
    ON dbo.DimProducto (IdProductoOrigen);
GO

CREATE TABLE dbo.FactVentas (
    IdVentaSK       INT IDENTITY(1,1) NOT NULL,
    IdVentaOrigen   INT            NOT NULL,
    IdClienteSK     INT            NOT NULL,
    IdProductoSK    INT            NOT NULL,
    Cantidad        INT            NOT NULL,
    PrecioUnitario  DECIMAL(12,2)  NOT NULL,
    Subtotal        DECIMAL(12,2)  NOT NULL,
    IVA             DECIMAL(12,2)  NOT NULL,
    Total           DECIMAL(12,2)  NOT NULL,
    FechaVenta      DATE           NOT NULL,
    Sucursal        VARCHAR(100)   NULL,
    FechaCarga      DATETIME       NOT NULL CONSTRAINT DF_FactVentas_FechaCarga DEFAULT (GETDATE()),
    CONSTRAINT PK_FactVentas PRIMARY KEY CLUSTERED (IdVentaSK),
    CONSTRAINT FK_FactVentas_Cliente  FOREIGN KEY (IdClienteSK)  REFERENCES dbo.DimCliente(IdClienteSK),
    CONSTRAINT FK_FactVentas_Producto FOREIGN KEY (IdProductoSK) REFERENCES dbo.DimProducto(IdProductoSK)
);
GO
CREATE UNIQUE NONCLUSTERED INDEX UX_FactVentas_Origen
    ON dbo.FactVentas (IdVentaOrigen);
GO

CREATE TABLE dbo.LogErrores (
    IdError          INT IDENTITY(1,1) NOT NULL,
    NombrePaquete    VARCHAR(100)  NOT NULL,
    NombreFlujo      VARCHAR(100)  NOT NULL,
    ArchivoOrigen    VARCHAR(150)  NOT NULL,
    FilaOrigen       VARCHAR(MAX)  NULL,
    DescripcionError VARCHAR(500)  NOT NULL,
    FechaError       DATETIME      NOT NULL CONSTRAINT DF_LogErrores_Fecha DEFAULT (GETDATE()),
    CONSTRAINT PK_LogErrores PRIMARY KEY CLUSTERED (IdError)
);
GO

CREATE TABLE dbo.LogProceso (
    IdProceso        INT IDENTITY(1,1) NOT NULL,
    NombrePaquete    VARCHAR(100)  NOT NULL,
    FechaInicio      DATETIME      NOT NULL,
    FechaFin         DATETIME      NULL,
    DuracionSegundos INT           NULL,
    TotalLeidos      INT           NULL,
    TotalInsertados  INT           NULL,
    TotalErrores     INT           NULL,
    Estatus          VARCHAR(50)   NOT NULL,
    Mensaje          VARCHAR(500)  NULL,
    CONSTRAINT PK_LogProceso PRIMARY KEY CLUSTERED (IdProceso)
);
GO

CREATE OR ALTER PROCEDURE dbo.usp_LogProceso_Inicio
    @NombrePaquete VARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.LogProceso (NombrePaquete, FechaInicio, Estatus, Mensaje)
    VALUES (@NombrePaquete, GETDATE(), 'EN PROCESO', 'Ejecucion iniciada');
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS IdProceso;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_LogProceso_Fin
    @TotalLeidos     INT = NULL,
    @TotalInsertados INT = NULL,
    @TotalErrores    INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE LP
    SET FechaFin         = GETDATE(),
        DuracionSegundos = DATEDIFF(SECOND, LP.FechaInicio, GETDATE()),
        TotalLeidos      = @TotalLeidos,
        TotalInsertados  = @TotalInsertados,
        TotalErrores     = @TotalErrores,
        Estatus          = CASE WHEN ISNULL(@TotalErrores,0) > 0
                                THEN 'COMPLETADO CON ERRORES' ELSE 'EXITOSO' END,
        Mensaje          = 'Proceso finalizado'
    FROM dbo.LogProceso LP
    WHERE LP.IdProceso = (SELECT MAX(IdProceso) FROM dbo.LogProceso
                          WHERE NombrePaquete = 'CargaVentas' AND Estatus = 'EN PROCESO');
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_LogError_Insert
    @NombrePaquete    VARCHAR(100),
    @NombreFlujo      VARCHAR(100),
    @ArchivoOrigen    VARCHAR(150),
    @FilaOrigen       VARCHAR(MAX),
    @DescripcionError VARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.LogErrores (NombrePaquete, NombreFlujo, ArchivoOrigen, FilaOrigen, DescripcionError)
    VALUES (@NombrePaquete, @NombreFlujo, @ArchivoOrigen, @FilaOrigen, @DescripcionError);
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Carga_DimCliente
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Limpio AS (
        SELECT
            TRY_CONVERT(INT, LTRIM(RTRIM(IdCliente)))                  AS IdClienteOrigen,
            UPPER(LTRIM(RTRIM(Nombre)))                                AS Nombre,
            UPPER(LTRIM(RTRIM(Apellido)))                              AS Apellido,
            NULLIF(LTRIM(RTRIM(Correo)), '')                           AS Correo,
            NULLIF(LTRIM(RTRIM(Telefono)), '')                         AS Telefono,
            UPPER(NULLIF(LTRIM(RTRIM(Ciudad)), ''))                    AS Ciudad,
            UPPER(NULLIF(LTRIM(RTRIM(Estado)), ''))                    AS Estado,
            UPPER(COALESCE(NULLIF(LTRIM(RTRIM(Pais)), ''), 'MEXICO'))  AS Pais,
            TRY_CONVERT(DATE, LTRIM(RTRIM(FechaRegistro)))             AS FechaRegistro,
            LTRIM(RTRIM(Activo))                                       AS Activo,
            ROW_NUMBER() OVER (PARTITION BY LTRIM(RTRIM(IdCliente))
                               ORDER BY (SELECT NULL))                 AS rn
        FROM stg.Clientes
    )
    MERGE dbo.DimCliente AS destino
    USING (
        SELECT IdClienteOrigen, Nombre, Apellido, Correo, Telefono, Ciudad, Estado, Pais, FechaRegistro
        FROM Limpio
        WHERE rn = 1
          AND Activo = '1'
          AND IdClienteOrigen IS NOT NULL
          AND Nombre   <> ''
          AND Apellido <> ''
    ) AS origen
    ON destino.IdClienteOrigen = origen.IdClienteOrigen
    WHEN NOT MATCHED THEN
        INSERT (IdClienteOrigen, Nombre, Apellido, Correo, Telefono, Ciudad, Estado, Pais, FechaRegistro)
        VALUES (origen.IdClienteOrigen, origen.Nombre, origen.Apellido, origen.Correo,
                origen.Telefono, origen.Ciudad, origen.Estado, origen.Pais, origen.FechaRegistro);
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Carga_DimProducto
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Limpio AS (
        SELECT
            TRY_CONVERT(INT, LTRIM(RTRIM(IdProducto)))  AS IdProductoOrigen,
            UPPER(LTRIM(RTRIM(NombreProducto)))         AS NombreProducto,
            LTRIM(RTRIM(Categoria))                     AS Categoria,
            TRY_CONVERT(DECIMAL(12,2), Precio)          AS Precio,
            TRY_CONVERT(DECIMAL(12,2), Costo)           AS Costo,
            LTRIM(RTRIM(Activo))                        AS Activo,
            ROW_NUMBER() OVER (PARTITION BY LTRIM(RTRIM(IdProducto))
                               ORDER BY (SELECT NULL))  AS rn
        FROM stg.Productos
    )
    MERGE dbo.DimProducto AS destino
    USING (
        SELECT IdProductoOrigen, NombreProducto, Categoria, Precio, Costo
        FROM Limpio
        WHERE rn = 1
          AND Activo = '1'
          AND IdProductoOrigen IS NOT NULL
          AND NombreProducto <> ''
          AND Precio > 0
          AND Costo  > 0
          AND EXISTS (SELECT 1 FROM dbo.CategoriaValida cv WHERE cv.Categoria = Limpio.Categoria)
    ) AS origen
    ON destino.IdProductoOrigen = origen.IdProductoOrigen
    WHEN NOT MATCHED THEN
        INSERT (IdProductoOrigen, NombreProducto, Categoria, Precio, Costo)
        VALUES (origen.IdProductoOrigen, origen.NombreProducto, origen.Categoria, origen.Precio, origen.Costo);
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Carga_FactVentas
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Limpio AS (
        SELECT
            TRY_CONVERT(INT, LTRIM(RTRIM(IdVenta)))     AS IdVentaOrigen,
            TRY_CONVERT(INT, LTRIM(RTRIM(IdCliente)))   AS IdClienteOrigen,
            TRY_CONVERT(INT, LTRIM(RTRIM(IdProducto)))  AS IdProductoOrigen,
            TRY_CONVERT(INT, LTRIM(RTRIM(Cantidad)))    AS Cantidad,
            TRY_CONVERT(DECIMAL(12,2), PrecioUnitario)  AS PrecioUnitario,
            TRY_CONVERT(DATE, LTRIM(RTRIM(FechaVenta))) AS FechaVenta,
            NULLIF(LTRIM(RTRIM(Sucursal)), '')          AS Sucursal,
            ROW_NUMBER() OVER (PARTITION BY LTRIM(RTRIM(IdVenta))
                               ORDER BY (SELECT NULL))  AS rn
        FROM stg.Ventas
    )
    MERGE dbo.FactVentas AS destino
    USING (
        SELECT
            l.IdVentaOrigen,
            dc.IdClienteSK,
            dp.IdProductoSK,
            l.Cantidad,
            l.PrecioUnitario,
            CAST(l.Cantidad * l.PrecioUnitario AS DECIMAL(12,2))        AS Subtotal,
            CAST(l.Cantidad * l.PrecioUnitario * 0.16 AS DECIMAL(12,2)) AS IVA,
            CAST(l.Cantidad * l.PrecioUnitario * 1.16 AS DECIMAL(12,2)) AS Total,
            l.FechaVenta,
            l.Sucursal
        FROM Limpio l
        INNER JOIN dbo.DimCliente  dc ON dc.IdClienteOrigen  = l.IdClienteOrigen
        INNER JOIN dbo.DimProducto dp ON dp.IdProductoOrigen = l.IdProductoOrigen
        WHERE l.rn = 1
          AND l.IdVentaOrigen IS NOT NULL
          AND l.Cantidad > 0
          AND l.PrecioUnitario > 0
          AND l.FechaVenta IS NOT NULL
    ) AS origen
    ON destino.IdVentaOrigen = origen.IdVentaOrigen
    WHEN NOT MATCHED THEN
        INSERT (IdVentaOrigen, IdClienteSK, IdProductoSK, Cantidad, PrecioUnitario,
                Subtotal, IVA, Total, FechaVenta, Sucursal)
        VALUES (origen.IdVentaOrigen, origen.IdClienteSK, origen.IdProductoSK, origen.Cantidad,
                origen.PrecioUnitario, origen.Subtotal, origen.IVA, origen.Total,
                origen.FechaVenta, origen.Sucursal);
END
GO

DROP TABLE IF EXISTS dbo.CategoriaValida;
GO
CREATE TABLE dbo.CategoriaValida (
    Categoria VARCHAR(100) NOT NULL PRIMARY KEY
);
GO

INSERT INTO dbo.CategoriaValida (Categoria) VALUES
('ALIMENTOS'),('DEPORTES'),('ELECTRÓNICA'),('HOGAR'),
('JUGUETES'),('OFICINA'),('ROPA'),('SALUD');
GO

PRINT 'Base de datos DWUTVTVentas creada correctamente.';
GO
