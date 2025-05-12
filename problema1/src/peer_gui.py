import tkinter as tk
from tkinter import ttk, scrolledtext, simpledialog
import random
import sys
from .mesh_peer import MeshPeer, TEAMS
from .gui_utils import dracula_startup_dialog, dracula_askstring, set_dracula_style

class PeerGUI:
    BG = '#282a36'
    FG = '#f8f8f2'
    ACCENT = '#bd93f9'
    SEL = '#44475a'
    BTN = '#6272a4'
    ENTRY_BG = '#44475a'
    ENTRY_FG = FG

    def __init__(self, root, alias, port):
        self.root = root
        set_dracula_style(self.root)
        self.alias = alias
        self.port = port
        self.host = '127.0.0.1'
        self.peer = MeshPeer(self.alias, self.host, self.port, self.on_event)
        self.peer.set_root(self.root)
        self.root.overrideredirect(True)
        self._force_taskbar_and_alt_tab()
        self._create_top_bar()
        self._setup_gui()
        self._refresh()
        self.root.bind('<Map>', self._on_restore)

    def _force_taskbar_and_alt_tab(self):
        if sys.platform == 'win32':
            try:
                import ctypes
                hwnd = ctypes.windll.user32.GetParent(self.root.winfo_id())
                GWL_EXSTYLE = -20
                WS_EX_APPWINDOW = 0x00040000
                WS_EX_TOOLWINDOW = 0x00000080
                style = ctypes.windll.user32.GetWindowLongW(hwnd, GWL_EXSTYLE)
                style = style | WS_EX_APPWINDOW
                style = style & ~WS_EX_TOOLWINDOW
                ctypes.windll.user32.SetWindowLongW(hwnd, GWL_EXSTYLE, style)
                # Forzar a mostrar en taskbar
                self.root.wm_withdraw()
                self.root.after(10, self.root.wm_deiconify)
            except Exception:
                pass

    def _create_top_bar(self):
        FUCHSIA = '#ff4fa3'
        self.top_bar = tk.Frame(self.root, bg=FUCHSIA, height=28)
        self.top_bar.pack(fill=tk.X, side=tk.TOP)
        self.top_bar.bind('<ButtonPress-1>', self._start_move)
        self.top_bar.bind('<B1-Motion>', self._on_move)
        # Título negro
        tk.Label(self.top_bar, text="P2P Mesh Grid", bg=FUCHSIA, fg="#111", font=("Segoe UI", 12, "bold")).pack(side=tk.LEFT, padx=14)
        # Botones estilo Mac con más contraste
        btn_frame = tk.Frame(self.top_bar, bg=FUCHSIA)
        btn_frame.pack(side=tk.RIGHT, padx=8)
        min_btn = tk.Canvas(btn_frame, width=18, height=18, bg=FUCHSIA, highlightthickness=0)
        min_btn.create_oval(3,3,15,15, fill="#ffd600", outline="#222", width=1.5)
        min_btn.bind('<Button-1>', lambda e: self._minimize())
        min_btn.pack(side=tk.LEFT, padx=2)
        close_btn = tk.Canvas(btn_frame, width=18, height=18, bg=FUCHSIA, highlightthickness=0)
        close_btn.create_oval(3,3,15,15, fill="#ff2222", outline="#222", width=1.5)
        close_btn.bind('<Button-1>', lambda e: self.on_close())
        close_btn.pack(side=tk.LEFT, padx=2)

    def _start_move(self, event):
        self._drag_x = event.x
        self._drag_y = event.y
    def _on_move(self, event):
        x = self.root.winfo_pointerx() - self._drag_x
        y = self.root.winfo_pointery() - self._drag_y
        self.root.geometry(f'+{x}+{y}')
    def _minimize(self):
        self.root.overrideredirect(False)
        self.root.iconify()

    def _on_restore(self, event=None):
        self.root.overrideredirect(True)

    def _setup_gui(self):
        bg = self.BG
        fg = self.FG
        accent = self.ACCENT
        sel = self.SEL
        btn = self.BTN
        entry_bg = self.ENTRY_BG
        entry_fg = self.ENTRY_FG
        f = ttk.Frame(self.root, padding=10)
        f.pack(fill=tk.BOTH, expand=True)
        self.root.configure(bg=bg)
        style = ttk.Style()
        style.theme_use('default')
        style.configure('.', background=bg, foreground=fg, fieldbackground=entry_bg)
        style.configure('TLabel', background=bg, foreground=fg)
        style.configure('TButton', background=btn, foreground=fg)
        style.configure('TFrame', background=bg)
        style.configure('TCombobox', fieldbackground=entry_bg, background=entry_bg, foreground=fg, selectbackground=sel, selectforeground=fg)
        style.map('TButton', background=[('active', accent)])
        style.configure('Dracula.TEntry', fieldbackground=entry_bg, foreground=fg, bordercolor=sel)
        self.log = scrolledtext.ScrolledText(f, height=8, state=tk.DISABLED, bg=entry_bg, fg=fg, insertbackground=fg, selectbackground=sel)
        self.log.pack(fill=tk.BOTH, expand=True)
        c = ttk.Frame(f)
        c.pack(fill=tk.X)
        ttk.Label(c, text="Equipo:").pack(side=tk.LEFT)
        self.team_combo = ttk.Combobox(c, values=TEAMS, width=8)
        self.team_combo.pack(side=tk.LEFT)
        self.team_combo.configure(background=entry_bg, foreground=fg)
        ttk.Button(c, text="Unirse", command=self.join_team).pack(side=tk.LEFT, padx=5)
        ttk.Button(c, text="Peers", command=self.show_peers).pack(side=tk.LEFT, padx=5)
        ttk.Label(c, text="Conectar a:").pack(side=tk.LEFT, padx=10)
        self.ip_entry = ttk.Entry(c, width=12)
        self.ip_entry.pack(side=tk.LEFT)
        self.ip_entry.configure(foreground=fg)
        self.ip_entry['style'] = 'Dracula.TEntry'
        self.port_entry = ttk.Entry(c, width=5)
        self.port_entry.pack(side=tk.LEFT)
        self.port_entry.configure(foreground=fg)
        self.port_entry['style'] = 'Dracula.TEntry'
        ttk.Button(c, text="Conectar", command=self.manual_connect).pack(side=tk.LEFT, padx=5)
        self.listo_btn = ttk.Button(c, text="Listo", command=lambda: self.peer.ready_and_maybe_start_game() if hasattr(self, 'peer') else None)
        self.listo_btn.pack(side=tk.LEFT, padx=5)
        self.status = ttk.Label(f, text="")
        self.status.pack(fill=tk.X)
        # --- NUEVO: Panel de información de juego y botón de tirar dado ---
        self.game_frame = ttk.Frame(f)
        self.game_frame.pack(side=tk.RIGHT, fill=tk.Y, padx=10, pady=5)
        # Frame vertical para timer y botón
        self.turn_col = tk.Frame(self.game_frame, bg=self.BG)
        self.turn_col.pack(fill=tk.Y, pady=5)
        # Panel de info y botón debajo del timer
        info_btn_frame = ttk.Frame(self.turn_col)
        info_btn_frame.pack(side=tk.TOP, fill=tk.BOTH, expand=True)
        self.game_info = tk.Label(info_btn_frame, text="", justify=tk.LEFT, anchor='nw', bg=self.BG, fg=self.FG, font=("Segoe UI", 11))
        self.game_info.pack(fill=tk.BOTH, expand=True, pady=(0,8))
        self.roll_btn = ttk.Button(info_btn_frame, text="Tirar dado", command=self._roll_dice)
        self.roll_btn.pack(fill=tk.X)
        self.roll_btn['state'] = tk.DISABLED
        self.root.protocol("WM_DELETE_WINDOW", self.on_close)
        # --- NUEVO: Panel de puntajes por equipo ---
        self.score_frame = ttk.Frame(f)
        self.score_frame.pack(side=tk.LEFT, anchor='sw', padx=2, pady=2, fill=tk.X)
        # Tabla con columna de equipo, puntos y alias del jugador actual
        self.score_table = ttk.Treeview(self.score_frame, columns=("equipo", "puntos", "jugador"), show='headings', height=4)
        self.score_table.heading('equipo', text='Equipo')
        self.score_table.heading('puntos', text='Puntos')
        self.score_table.heading('jugador', text='Jugador actual')
        self.score_table.column('equipo', width=70, anchor='center')
        self.score_table.column('puntos', width=60, anchor='center')
        self.score_table.column('jugador', width=110, anchor='center')
        self.score_table.pack(side=tk.LEFT, fill=tk.X, expand=True)
        # Frame a la derecha de la tabla para el botón y el label de tiempo
        self.score_side_frame = ttk.Frame(self.score_frame)
        self.score_side_frame.pack(side=tk.LEFT, fill=tk.Y, padx=(6,0))
        self.order_btn = ttk.Button(self.score_side_frame, text="Ver orden", command=self.show_order_window)
        self.order_btn.pack(side=tk.TOP, pady=(0,8), anchor='n', fill=tk.X)
        self.timer_label = tk.Label(self.score_side_frame, text="", bg=self.BG, fg=self.FG, font=("Segoe UI", 11, "bold"))
        self.timer_label.pack(side=tk.TOP, anchor='n', pady=(0,2), fill=tk.X)
        # Label para el número de turno
        self.turn_number_label = tk.Label(self.score_side_frame, text="", bg=self.BG, fg=self.FG, font=("Segoe UI", 11, "bold"))
        self.turn_number_label.pack(side=tk.TOP, anchor='n', pady=(0,2), fill=tk.X)

    def _roll_dice(self):
        # Lanza el dado y hace broadcast del resultado a todos los peers
        if hasattr(self, 'peer'):
            self.peer.lanzar_dado()  # Usar la función correcta de MeshPeer

    def show_game_panel(self, show=True):
        # Nunca ocultar el panel de tirar dado, solo deshabilitar el botón
        self.game_frame.pack(side=tk.RIGHT, fill=tk.Y, padx=10, pady=5)

    def update_score_table(self):
        # Borra y actualiza la tabla de puntajes
        for row in self.score_table.get_children():
            self.score_table.delete(row)
        if hasattr(self.peer, '_marcador') and hasattr(self.peer, '_turno_actual'):
            for equipo in sorted(self.peer._marcador.keys()):
                puntos = self.peer._marcador[equipo]
                jugador = self.peer._turno_actual.get(equipo)
                if jugador is not None:
                    alias = self.peer.alias if jugador == self.peer.me() else self.peer.peers.get(jugador, str(jugador))
                else:
                    alias = "-"
                self.score_table.insert('', 'end', values=(equipo, puntos, alias))

    def show_order_window(self):
        win = tk.Toplevel(self.root)
        set_dracula_style(win)
        win.title("Orden de jugadores por equipo")
        self._center_window(win, width=350, height=300)
        text = tk.Text(win, bg=self.BG, fg=self.FG, font=("Segoe UI", 11), state=tk.NORMAL, wrap=tk.WORD)
        text.pack(fill=tk.BOTH, expand=True, padx=8, pady=8)
        if hasattr(self.peer, '_orden'):
            for team in sorted(self.peer._orden.keys()):
                jugadores = self.peer._orden[team]
                text.insert(tk.END, f"Equipo {team}:\n")
                for idx, jugador in enumerate(jugadores):
                    alias = self.peer.alias if jugador == self.peer.me() else self.peer.peers.get(jugador, str(jugador))
                    actual = self.peer._turno_actual.get(team)
                    marker = " ← (turno)" if actual == jugador else ""
                    tu = "<TU> " if jugador == self.peer.me() else ""
                    text.insert(tk.END, f"  {idx+1}. {tu}{alias}{marker}\n")
                text.insert(tk.END, "\n")
        else:
            text.insert(tk.END, "No hay información de orden disponible.")
        text.config(state=tk.DISABLED)
        ttk.Button(win, text="Cerrar", command=win.destroy).pack(pady=4)

    def _center_window(self, win, width=350, height=300):
        # Centra la ventana win sobre la ventana principal
        self.root.update_idletasks()
        x = self.root.winfo_x()
        y = self.root.winfo_y()
        w = self.root.winfo_width()
        h = self.root.winfo_height()
        # Si la ventana principal aún no tiene tamaño, usar el centro de la pantalla
        if w < 50 or h < 50:
            sw = self.root.winfo_screenwidth()
            sh = self.root.winfo_screenheight()
            x = (sw - width) // 2
            y = (sh - height) // 2
        else:
            x = x + (w - width) // 2
            y = y + (h - height) // 2
        win.geometry(f"{width}x{height}+{x}+{y}")
        win.lift()
        win.transient(self.root)
        win.grab_set()

    def update_game_info(self, current_players, team_players, team_map, scores):
        # Mostrar info de ronda, jugadores actuales y puntajes
        lines = []
        if team_players:
            lines.append("Jugadores de ronda:")
            for team in sorted(team_players.keys()):
                jugadores = team_players[team]
                alias_list = [self.peer.alias if p == self.peer.me() else self.peer.peers.get(p, str(p)) for p in jugadores]
                actual = current_players.get(team)
                actual_alias = self.peer.alias if actual == self.peer.me() else self.peer.peers.get(actual, str(actual))
                turn_marker = " <---" if actual == self.peer.me() else ""
                lines.append(f"Equipo {team}: {', '.join(alias_list)} | Turno: {actual_alias}{turn_marker} | Puntos: {scores.get(team,0)}")
        self.game_info.config(text='\n'.join(lines))
        self.update_score_table()

    def enable_roll(self, enable=True):
        # Forzar actualización visual inmediata
        self.roll_btn['state'] = tk.NORMAL if enable else tk.DISABLED
        self.roll_btn.update_idletasks()

    def lock_team_and_ready(self):
        self.team_combo.config(state=tk.DISABLED)
        for child in self.team_combo.master.winfo_children():
            if isinstance(child, ttk.Button) and child['text'] in ('Unirse', 'Listo'):
                child.config(state=tk.DISABLED)

    def on_event(self, kind, *args):
        if kind == 'enable_roll':
            self.enable_roll(args[0])
            return
        if kind == 'update_scores':
            self.update_score_table()
            return
        if kind == 'turn_timer':
            # Mostrar el valor del temporizador en el label
            self.timer_label.config(text=f"⏳ Tiempo restante: {args[0]}s")
            return
        if kind == 'turn_start_timer':
            # Mostrar el valor inicial del temporizador al iniciar turno
            self.timer_label.config(text=f"⏳ Tiempo restante: {args[0]}s")
            return
        if kind == 'turn_number':
            # Mostrar el número de turno debajo del timer
            self.turn_number_label.config(text=f"Turno actual: {args[0]}")
            return
        if kind == 'log':
            msg = args[0]
            self.log.config(state=tk.NORMAL)
            self.log.insert(tk.END, msg+"\n")
            self.log.see(tk.END)
            self.log.config(state=tk.DISABLED)
            # Bloquear botones si inicia la partida
            if '[Juego]' in msg and ('¡Comienza la partida!' in msg or 'Enviando inicio de partida a todos' in msg):
                self.lock_team_and_ready()
            # Habilitar botón de tirar dado si el log indica que es mi turno
            if '[Juego] Turno de' in msg and self.peer.team:
                # Buscar si soy el jugador de mi equipo en el turno
                try:
                    for team, jugador in self.peer._turno_actual.items():
                        if team == self.peer.team and jugador == self.peer.me():
                            self.enable_roll(True)
                            break
                    else:
                        self.enable_roll(False)
                except Exception:
                    self.enable_roll(False)
        elif kind == 'join_req':
            peer, team, display = args
            win = tk.Toplevel(self.root)
            set_dracula_style(win)
            win.title("Solicitud de unión a equipo")
            ttk.Label(win, text=f"{display} solicita unirse a {team}.").pack(padx=10, pady=10)
            responded = {'voto': False}
            def votar(si):
                if not responded['voto']:
                    self.peer.send_to(peer, {'type': 'join_vote', 'team': team, 'from': [self.peer.host, self.peer.port], 'vote': si})
                    self.on_event('log', f"Voto {'SI' if si else 'NO'} para {display} en {team}")
                    responded['voto'] = True
                    win.destroy()
            ttk.Button(win, text="Sí", command=lambda: votar(True)).pack(side=tk.LEFT, padx=10, pady=10)
            ttk.Button(win, text="No", command=lambda: votar(False)).pack(side=tk.LEFT, padx=10, pady=10)
            def timeout():
                if not responded['voto']:
                    votar(False)
            win.after(10000, timeout)
        elif kind == 'game_over':
            # args[0] es el resultado {'ganador': equipo} o {'empate': [equipos]}
            self.root.after(100, lambda: self._show_resultado(args[0]))
            return

    def _show_resultado(self, resultado):
        # Cerrar la ventana principal y mostrar la pantalla de resultado
        self.root.withdraw()
        try:
            from .resultado_gui import ResultadoGUI
        except ImportError:
            import sys
            import os
            sys.path.append(os.path.dirname(__file__))
            from .resultado_gui import ResultadoGUI
        equipos = list(self.peer._marcador.keys()) if hasattr(self.peer, '_marcador') else []
        puntajes = dict(self.peer._marcador) if hasattr(self.peer, '_marcador') else {}
        def replay():
            import sys, os
            os.execl(sys.executable, sys.executable, *sys.argv)
        def salir():
            self.root.destroy()
        resultado_win = ResultadoGUI(resultado, equipos, on_replay=replay, on_exit=salir, equipos_puntaje=puntajes)
        resultado_win.run()

    def on_game_event(self, kind, *args):
        # Redirigir eventos de GameModule a la GUI
        if kind == 'log':
            self.on_event('log', *args)
        elif kind == 'countdown':
            self.status.config(text=f"Comenzando en {args[0]}..." if args[0] > 0 else "")
        elif kind == 'turn':
            current_players, scores = args
            self.show_game_panel(True)
            # Mostrar info de ronda y jugadores actuales
            self.update_game_info(current_players, self.peer._team_players, self.peer.team_map, scores)
            # Habilitar botón solo si soy el jugador de mi equipo en esta ronda y no he tirado
            my_team = self.peer.team
            enable = my_team in current_players and current_players[my_team] == self.peer.me() and not self.peer._rolled_this_turn.get(self.peer.me(), False)
            self.enable_roll(enable)
        elif kind == 'roll':
            who, roll, scores = args
            self.on_event('log', f"{who} sacó {roll}. Puntuaciones: {scores}")
            self.update_game_info(self.peer._current_players, self.peer._team_players, self.peer.team_map, scores)
            # Deshabilitar el botón de tirar dado para todos los jugadores que ya tiraron
            my_team = self.peer.team
            if my_team in self.peer._current_players and self.peer._current_players[my_team] == self.peer.me():
                if self.peer._rolled_this_turn.get(self.peer.me(), False):
                    self.enable_roll(False)
        elif kind == 'game_end':
            self.enable_roll(False)
            self.status.config(text=f"¡Equipo ganador: {args[0]} con {args[1]} puntos!")

    def join_team(self):
        team = self.team_combo.get()
        if not team:
            return
        if self.peer.team == team:
            self.on_event('log', f"Ya eres parte de {team}. No se realiza ninguna acción.")
            return
        miembros = [k for k, t in self.peer.teams.items() if t == team]
        if len(miembros) == 0:
            self.peer.team = team
            self.peer.teams[(self.peer.host, self.peer.port)] = team
            self.status.config(text=f"¡Unido a {team} (sin votos)!")
            self.on_event('log', f"¡Unido a {team} (sin votos)!")
            self.peer.broadcast_peers()
            self.peer.broadcast({'type': 'team_update', 'peer': [self.peer.host, self.peer.port], 'team': team})
            return
        self.on_event('log', f"Solicitando unirse a {team}...")
        self.peer._joining = True
        self.peer._proposed = team
        self.peer._votes = 0
        self.peer._voters = set()
        self.peer._total_voters = set(miembros)
        self.peer.broadcast({'type': 'join_req', 'team': team, 'from': [self.peer.host, self.peer.port]})
        self.status.config(text=f"Esperando votos para {team}...")
        self.root.after(11000, self._check_vote_timeout)

    def _check_vote_timeout(self):
        if hasattr(self.peer, '_joining') and self.peer._joining:
            total = len(getattr(self.peer, '_total_voters', []))
            votos_si = getattr(self.peer, '_votes', 0)
            votos_no = len(getattr(self.peer, '_voters', set())) - votos_si
            self.on_event('log', f"No se alcanzó la mayoría para unirse a {self.peer._proposed}. Votos SÍ: {votos_si}, NO: {votos_no}, de {total}.")
            self.peer._joining = False
            self.status.config(text=f"No se alcanzó mayoría para {self.peer._proposed}")

    def show_peers(self):
        win = tk.Toplevel(self.root)
        set_dracula_style(win)
        win.title("Peers conectados")
        # Centrar sobre la ventana principal y aumentar tamaño
        self._center_window(win, width=520, height=340)
        tree = ttk.Treeview(win, columns=("alias","ip","team","listo"), show='headings')
        tree.heading('alias', text='Alias')
        tree.heading('ip', text='IP:Puerto')
        tree.heading('team', text='Equipo')
        tree.heading('listo', text='Listo')
        tree.column('alias', width=120, anchor='center')
        tree.column('ip', width=120, anchor='center')
        tree.column('team', width=80, anchor='center')
        tree.column('listo', width=60, anchor='center')
        # Obtener lista de peers listos
        ready_peers = set(getattr(self.peer, 'ready_peers', set()))
        for (h,p), alias in self.peer.peers.items():
            team = self.peer.teams.get((h,p), None)
            listo = '✔' if (h,p) in ready_peers else ''
            tree.insert('', 'end', values=(alias, f"{h}:{p}", team if team else '-', listo))
        # Mostrar también el propio peer, con <TU> antes del alias
        my_team = self.peer.teams.get((self.peer.host, self.peer.port), None)
        my_listo = '✔' if (self.peer.host, self.peer.port) in ready_peers else ''
        tree.insert('', 'end', values=(f"<TU>{self.alias}", f"{self.peer.host}:{self.peer.port}", my_team if my_team else '-', my_listo))
        tree.pack(fill=tk.BOTH, expand=True)
        ttk.Button(win, text="Cerrar", command=win.destroy).pack()

    def manual_connect(self):
        ip = self.ip_entry.get().strip()
        if not ip:
            ip = '127.0.0.1'
        try:
            port = int(self.port_entry.get())
            self.on_event('log', f"Conectando a {ip}:{port}...")
            self.peer.connect_to((ip, port))
        except Exception as e:
            self.on_event('log', f"Error: {e}")

    def _refresh(self):
        pastel_colors = [
            '#ffb3ba', '#ffc2b6', '#ffd1b2', '#ffdfba', '#fff6ba', '#f6ffba', '#e0ffba', '#baffc9',
            '#baffe0', '#baf6ff', '#bae1ff', '#c6baff', '#d5baff', '#eabaff', '#ffbafc', '#ffbae1',
            '#ffbada', '#ffbacb', '#ffbac0', '#ffb3ba'
        ]
        if not hasattr(self, '_alias_color_idx'):
            self._alias_color_idx = 0
        color = pastel_colors[self._alias_color_idx % len(pastel_colors)]
        self._alias_color_idx = (self._alias_color_idx + 1) % len(pastel_colors)
        alias_text = f"Alias: {self.alias}"
        status_text = f"{alias_text} | Puerto: {self.port} | Equipo: {self.peer.team or '-'} | Peers: {len(self.peer.peers)}"
        self.status.config(text=status_text)
        try:
            self.status.config(foreground=color)
        except Exception:
            pass
        # Deshabilitar campos de conexión si la red tiene al menos 2 nodos (yo + otro)
        if len(self.peer.peers) + 1 >= 2:
            try:
                self.ip_entry.config(state=tk.DISABLED)
                self.port_entry.config(state=tk.DISABLED)
                for child in self.ip_entry.master.winfo_children():
                    if isinstance(child, ttk.Button) and child['text'] == 'Conectar':
                        child.config(state=tk.DISABLED)
            except Exception:
                pass
        else:
            try:
                self.ip_entry.config(state=tk.NORMAL)
                self.port_entry.config(state=tk.NORMAL)
                for child in self.ip_entry.master.winfo_children():
                    if isinstance(child, ttk.Button) and child['text'] == 'Conectar':
                        child.config(state=tk.NORMAL)
            except Exception:
                pass
        # --- NUEVO: Deshabilitar 'Listo' si no tienes equipo ---
        try:
            if hasattr(self, 'listo_btn'):
                if not self.peer.team:
                    self.listo_btn.config(state=tk.DISABLED)
                else:
                    self.listo_btn.config(state=tk.NORMAL)
        except Exception:
            pass
        # Forzar que todos los peers conocidos tengan equipo (None si no)
        for peer in list(self.peer.peers.keys()) + [self.peer.me()]:
            if peer not in self.peer.teams:
                self.peer.teams[peer] = None
        self.root.after(80, self._refresh)

    def on_close(self):
        self.peer.graceful_leave()
        self.root.destroy()
