import tkinter as tk
import sys
import os

# Colores estilo Dracula + fucsia
BG = '#282a36'
FG = '#f8f8f2'
FUSCHIA = '#ff4fa3'
BTN_BG = '#6272a4'
BTN_FG = FG
BTN_ACTIVE = '#bd93f9'
TOPBAR_HEIGHT = 36

class ResultadoGUI:
    def __init__(self, resultado, equipos, on_replay=None, on_exit=None, equipos_puntaje=None):
        self.root = tk.Tk()
        self.root.title('Resultado del Juego')
        self.root.configure(bg=BG)
        self.root.geometry('520x370')
        self.root.resizable(False, False)
        self.on_replay = on_replay
        self.on_exit = on_exit
        self.equipos_puntaje = equipos_puntaje or {}
        self._force_taskbar_and_alt_tab()
        self._build_ui(resultado, equipos)
        self.root.protocol('WM_DELETE_WINDOW', self.exit)

    def _build_ui(self, resultado, equipos):
        # Mensaje principal
        frame = tk.Frame(self.root, bg=BG)
        frame.pack(expand=True, fill=tk.BOTH)
        if 'ganador' in resultado:
            msg = f"¡EL EQUIPO {resultado['ganador']} GANÓ!"
        elif 'empate' in resultado:
            eqs = ', '.join(str(e) for e in resultado['empate'])
            msg = f"¡EMPATE!"
        else:
            msg = "JUEGO FINALIZADO"
        label = tk.Label(frame, text=msg, bg=BG, fg=FUSCHIA, font=('Segoe UI Black', 24, 'bold'), pady=30)
        label.pack()
        # Tabla de puntuación
        table_frame = tk.Frame(frame, bg=BG)
        table_frame.pack(pady=(0, 10))
        columns = ("Equipo", "Puntos")
        table = tk.Frame(table_frame, bg=BG)
        table.pack()
        # Encabezados
        for j, col in enumerate(columns):
            tk.Label(table, text=col, bg=BG, fg=FG, font=("Segoe UI Semibold", 13), padx=18, pady=4).grid(row=0, column=j)
        # Filas de puntaje
        for i, equipo in enumerate(equipos):
            puntos = self._get_puntos_equipo(equipo)
            tk.Label(table, text=str(equipo), bg=BG, fg=FUSCHIA, font=("Segoe UI", 13, "bold"), padx=18, pady=2).grid(row=i+1, column=0)
            tk.Label(table, text=str(puntos), bg=BG, fg=FG, font=("Segoe UI", 13), padx=18, pady=2).grid(row=i+1, column=1)
        # Botones modernos, más pequeños y con texto más corto
        btn_frame = tk.Frame(frame, bg=BG)
        btn_frame.pack(pady=18)
        style = {'font': ('Segoe UI Semibold', 13), 'bg': BTN_BG, 'fg': BTN_FG, 'activebackground': BTN_ACTIVE, 'activeforeground': FUSCHIA, 'bd': 0, 'relief': tk.FLAT, 'width': 12, 'height': 1, 'cursor': 'hand2'}
        btn_replay = tk.Button(btn_frame, text='REINICIAR', command=self.replay, **style)
        btn_replay.grid(row=0, column=0, padx=16)
        btn_exit = tk.Button(btn_frame, text='SALIR', command=self.exit, **style)
        btn_exit.grid(row=0, column=1, padx=16)

    def _get_puntos_equipo(self, equipo):
        # Buscar el puntaje del equipo si se pasó como atributo
        if hasattr(self, 'equipos_puntaje'):
            return self.equipos_puntaje.get(equipo, '-')
        # Si no, intentar leer de un archivo o variable global
        return '-'

    def _force_taskbar_and_alt_tab(self):
        if sys.platform == 'win32':
            try:
                import ctypes
                hwnd = ctypes.windll.user32.GetParent(self.root.winfo_id())
                GWL_EXSTYLE = -20
                WS_EX_APPWINDOW = 0x00040000
                WS_EX_TOOLWINDOW = 0x00000080
                style = ctypes.windll.user32.GetWindowLong(hwnd, GWL_EXSTYLE)
                style = style | WS_EX_APPWINDOW
                style = style & ~WS_EX_TOOLWINDOW
                ctypes.windll.user32.SetWindowLong(hwnd, GWL_EXSTYLE, style)
                self.root.wm_withdraw()
                self.root.after(10, self.root.wm_deiconify)
            except Exception:
                pass

    def replay(self):
        if self.on_replay:
            self.on_replay()
        else:
            python = sys.executable
            os.execl(python, python, *sys.argv)

    def exit(self, event=None):
        # Cerrar la ventana de forma segura, ignorando múltiples llamadas
        try:
            self.root.quit()
            self.root.destroy()
        except Exception:
            pass
        if self.on_exit:
            self.on_exit()

    def run(self):
        self.root.mainloop()

# Ejemplo de uso:
if __name__ == '__main__':
    resultado = {'ganador': 'ROJO'}
    equipos = ['ROJO', 'AZUL', 'VERDE']
    equipos_puntaje = {'ROJO': 10, 'AZUL': 8, 'VERDE': 6}
    app = ResultadoGUI(resultado, equipos, equipos_puntaje=equipos_puntaje)
    app.run()
