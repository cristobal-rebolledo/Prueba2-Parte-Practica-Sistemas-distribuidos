from src.peer_gui import PeerGUI, dracula_startup_dialog
import tkinter as tk

if __name__ == "__main__":
    root = tk.Tk()
    root.withdraw()  # Oculta la ventana principal
    root.title("P2P Mesh Grid")
    alias, port = dracula_startup_dialog(root)
    if not alias or not port:
        root.destroy()
        exit()
    gui = PeerGUI(root, alias, port)
    root.geometry("700x480")
    root.deiconify()  # Muestra la ventana principal solo después del diálogo
    root.mainloop()