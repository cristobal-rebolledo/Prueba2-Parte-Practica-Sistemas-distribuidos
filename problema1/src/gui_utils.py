import tkinter as tk
import sys

# Colores Dracula
BG = '#282a36'
FG = '#f8f8f2'
ACCENT = '#bd93f9'
BTN = '#6272a4'
ENTRY_BG = '#44475a'


def set_dracula_style(win):
    win.configure(bg=BG)
    try:
        win.option_add('*Background', BG)
        win.option_add('*Foreground', FG)
        win.option_add('*TCombobox*Listbox.background', ENTRY_BG)
        win.option_add('*TCombobox*Listbox.foreground', FG)
    except Exception:
        pass


def dracula_startup_dialog(root):
    win = tk.Toplevel(root)
    set_dracula_style(win)
    win.title("Configuración inicial")
    win.geometry("370x150+400+200")
    win.grab_set()

    # --- Hack para Alt+Tab y barra de tareas en Windows ---
    if sys.platform == 'win32':
        try:
            import ctypes
            hwnd = ctypes.windll.user32.GetParent(win.winfo_id())
            GWL_EXSTYLE = -20
            WS_EX_APPWINDOW = 0x00040000
            WS_EX_TOOLWINDOW = 0x00000080
            style = ctypes.windll.user32.GetWindowLongW(hwnd, GWL_EXSTYLE)
            style = style | WS_EX_APPWINDOW
            style = style & ~WS_EX_TOOLWINDOW
            ctypes.windll.user32.SetWindowLongW(hwnd, GWL_EXSTYLE, style)
            win.wm_withdraw()
            win.after(10, win.wm_deiconify)
        except Exception:
            pass

    frm = tk.Frame(win, bg=BG)
    frm.pack(expand=True, fill=tk.BOTH, padx=24, pady=18)
    tk.Label(frm, text="Alias", bg=BG, fg=FG, anchor='w', font=("Segoe UI", 11, "bold"), width=8).grid(row=0, column=0, sticky='e', pady=(0,8), padx=(0,8))
    alias_var = tk.StringVar()
    alias_entry = tk.Entry(frm, textvariable=alias_var, bg=ENTRY_BG, fg=FG, insertbackground=FG, font=("Segoe UI", 11), width=22)
    alias_entry.grid(row=0, column=1, sticky='ew', pady=(0,8))
    alias_entry.focus_set()
    tk.Label(frm, text="Puerto", bg=BG, fg=FG, anchor='w', font=("Segoe UI", 11, "bold"), width=8).grid(row=1, column=0, sticky='e', pady=(0,8), padx=(0,8))
    port_var = tk.StringVar()
    port_entry = tk.Entry(frm, textvariable=port_var, bg=ENTRY_BG, fg=FG, insertbackground=FG, font=("Segoe UI", 11), width=22)
    port_entry.grid(row=1, column=1, sticky='ew', pady=(0,8))
    btn = tk.Button(frm, text="Iniciar", command=lambda: ok(), bg=BTN, fg=FG, activebackground=ACCENT, font=("Segoe UI", 11, "bold"), width=12)
    btn.grid(row=2, column=0, columnspan=2, pady=(8,0))
    frm.grid_columnconfigure(1, weight=1)
    import random
    alias_var.set(f"Peer{random.randint(100,999)}")
    port_var.set(str(random.randint(5000, 9000)))
    val = []
    def ok():
        alias = alias_var.get().strip() or f"Peer{random.randint(100,999)}"
        try:
            port = int(port_var.get())
        except Exception:
            port = random.randint(5000, 9000)
        val.append((alias, port))
        win.destroy()
    def on_close():
        val.clear()
        win.destroy()
    win.protocol("WM_DELETE_WINDOW", on_close)
    win.bind('<Return>', lambda e: ok())
    root.wait_window(win)
    if val:
        return val[0]
    return (None, None)


def dracula_askstring(root, title, prompt):
    win = tk.Toplevel(root)
    set_dracula_style(win)
    win.title(title)
    win.grab_set()
    tk.Label(win, text=prompt, bg=BG, fg=FG).pack(padx=10, pady=10)
    entry = tk.Entry(win, bg=ENTRY_BG, fg=FG, insertbackground=FG)
    entry.pack(padx=10, pady=10)
    entry.focus_set()
    val = []
    def ok():
        val.append(entry.get())
        win.destroy()
    tk.Button(win, text="OK", command=ok, bg=BTN, fg=FG, activebackground=ACCENT).pack(pady=5)
    win.bind('<Return>', lambda e: ok())
    root.wait_window(win)
    return val[0] if val else None
