import AppKit

/// In-app help for end users (first run, routing model, diagnostics).
final class HelpWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Справка — myVPN"
        window.minSize = NSSize(width: 420, height: 320)
        self.init(window: window)
        window.center()

        let scroll = NSScrollView(frame: window.contentView!.bounds)
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]
        scroll.borderType = .noBorder

        let tv = NSTextView(frame: scroll.bounds)
        tv.isEditable = false
        tv.isRichText = false
        tv.font = .systemFont(ofSize: 13)
        tv.string = Self.helpText
        tv.autoresizingMask = [.width]
        tv.textContainerInset = NSSize(width: 16, height: 16)
        scroll.documentView = tv
        window.contentView = scroll
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private static let helpText = """
    myVPN — клиент в строке меню macOS

    Что делает
    • Поднимает несколько WireGuard-туннелей через ядро sing-box
    • Маршрутизирует: российские ресурсы напрямую, домашние сети по AllowedIPs профиля Home, остальной интернет через egress (macbook)
    • Умеет смонтировать NAS по SMB и проверить состояние (Диагностика)

    Первый запуск
    1. Если в корневом меню есть «Установить помощника» — нажми (один раз пароль администратора). Когда помощник ок — пункта не будет.
    2. Настройки → Настройки подключения… — импортируйте или вставьте два .conf (egress + home)
    3. При необходимости заполните LAN / NAS / DNS на вкладке «Маршруты / NAS»
    4. «Обновить RU», затем «Включить»

    Настройка
    • Импорт файла, вставка из буфера или правка текста вручную
    • Home AllowedIPs задают, какие подсети идут в домашний туннель
    • Удаление помощника — Настройки → Удалить системный помощник
    • Ключи никогда не уходят в облако — только ~/.config/wireguard на этом Mac

    Обновление
    • Меню → Проверить обновление — скачает релиз с GitHub и заменит приложение
    • «Обновить RU» — отдельно: базы доменов/IP для маршрутизации по РФ

    Если что-то не работает
    • Диагностика — снимок каналов и понятный вердикт
    • Лог меню: ~/Library/Logs/myvpn-menubar.log
    • Лог ядра: ~/.config/myvpn/sing-box.log

    Требования: macOS 13+, Homebrew sing-box (обычно ставится вместе с runtime).
    """
}
