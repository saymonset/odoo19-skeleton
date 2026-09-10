# 📊 Reporte Contable de Gastos (Odoo 19)

Procedimiento para llevar el **reporte contable de gastos de la empresa** usando los módulos OCA ya instalados. No requiere instalar módulos nuevos.

## Estado del entorno (verificado)

| Módulo | Estado |
|---|---|
| `account_financial_report` | ✅ instalado |
| `account_usability` | ✅ instalado |
| `date_range` | ✅ instalado |
| `hr_expense` | ❌ sin instalar (no necesario para este caso) |

Consulta de verificación:

```bash
docker exec odoo-db19-n8n psql -U odoo -d dbodoo19 -tAc \
"SELECT name, state FROM ir_module_module \
 WHERE name IN ('account_financial_report','account_usability','date_range') ORDER BY name;"
```

## 1. Registrar los gastos

Los gastos se registran como **facturas de proveedor** o **asientos contables** usando cuentas de la clase 6 (según el plan contable local/venezolano):

- **Factura de proveedor**: Contabilidad → Facturación → Nueva factura → Tipo *Proveedor* → cuenta de gasto 6xxx.
- **Asiento directo**: Contabilidad → Asientos → Nuevo → líneas con cuentas de gasto.

## 2. Clasificar las cuentas de gasto

Contabilidad → Configuración → Plan de cuentas.

Agrupar las cuentas 6xxx por categoría para una lectura limpia: suministros, servicios, transporte, nómina, arrendamiento, etc.

## 3. Generar el reporte

Contabilidad → Reportes (módulo `account_financial_report`):

- **General Ledger (Libro Mayor)**: filtrar a cuentas 6xxx por rango de fechas.
- **Trial Balance (Balance de comprobación)**: ver el total de gastos por cuenta.
- Usar **rangos de fechas** (apoyo del módulo `date_range`) para periodos mensuales/anuales.

## 4. Opcional: agrupar mejor

Crear **grupos de cuentas** para que el reporte consolide el total de gasto por categoría en lugar de cuenta por cuenta.

## Alcance

No hay cambios de código ni instalación de módulos OCA nuevos. Toda la operación es de configuración y uso en la interfaz de Odoo.
