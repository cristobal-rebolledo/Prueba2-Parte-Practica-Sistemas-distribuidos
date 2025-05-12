## Descripción 
Este proyecto permite crear gráficos estadísticos basados en los logs centralizados del Problema B.2 usando Python y Jupyter Notebook. Está diseñado para ejecutarse localmente en un entorno de Anaconda.

Carga datos de logs centralizados (formato .gz que contiene archivo .json)

Filtra y transforma los datos en un DataFrame de Pandas

Genera visualizaciones interactivas con ipywidgets y matplotlib

Conteo de acciones por ventanas de tiempo

Filtros por tipo de acción y rango de tiempo

Ejes dinámicos o fijos según configuración

## Intalar 
python versión >= 3.0
Anaconda última versión
## Instalar librerias

Si estás usando Anaconda, puedes instalar las dependencias necesarias ejecutando:
conda install pandas matplotlib ipywidgets

Para usuarios de pip, puedes usar:
pip install pandas matplotlib ipywidgets


## Cómo usarlo

1. Abre notebook.ipynb en Jupyter Notebook o JupyterLab también puedes hacerlo desde la consola de Anaconda Prompt y ejecuta "jupyter notebook" para abrir jupyter y selecciona el notebook.

2. En el archivo .env en la variable de entorno PATH_ARCHIVO pon la ruta del archivo de logcentralizado.

3. Ejecuta las celdas paso a paso

4. Interactúa con los widgets para explorar los datos