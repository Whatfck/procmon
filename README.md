# procmon

**procmon** es una pequeña herramienta de monitoreo de procesos para Linux, desarrollada en **Bash** y construida directamente sobre la información que expone el kernel mediante el sistema de archivos `/proc`.

El proyecto se encuentra actualmente **en desarrollo** y forma parte de un taller práctico sobre procesos y planificación de CPU en Linux.

## Estado actual

Actualmente, `procmon` permite:

* Detectar los procesos activos recorriendo `/proc`.
* Obtener el **PID** de cada proceso.
* Leer el nombre del proceso desde `/proc/<pid>/status`.
* Obtener el estado actual del proceso.
* Mostrar la información directamente en la terminal.

Ejemplo de salida:

```text
PID      PROCESS              STATE
1        systemd              S (sleeping)
1354     zsh                  S (sleeping)
1358     zsh                  S (sleeping)
1337     stress-ng            R (running)
```

La herramienta **no utiliza `ps`, `top` ni `htop`** para obtener esta información. Los datos se leen directamente desde `/proc`

## Requisitos

* Linux
* Bash

No requiere instalar dependencias adicionales para su funcionamiento actual.

## Instalación
```bash
# Clona el repositorio:
git clone https://github.com/Whatfck/procmon

#Entra al directorio:
cd procmon

# Da permisos de ejecución:
chmod +x monitor.sh

# Y ejecuta la herramienta:
./monitor.sh
```



## ¿Cómo funciona?

Linux expone información sobre cada proceso mediante un directorio cuyo nombre corresponde a su PID:

```text
/proc/1/
/proc/1354/
/proc/1358/
...
```

Dentro de cada directorio existe un archivo `status` que contiene información sobre el proceso.

Por ejemplo:

```bash
cat /proc/1354/status
```

`procmon` recorre automáticamente estos directorios y extrae de `status` campos como:

```text
Name:
State:
```

para construir el listado mostrado en la terminal.

---

**Proyecto en desarrollo**
**@Whatfck** - 2026