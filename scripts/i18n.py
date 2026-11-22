#!/usr/bin/env python3
"""多语言：生成 Resources/Localization/<lang>.lproj/Localizable.strings 并检查覆盖率。

键是代码里的简体中文原文。用法：
    python3 scripts/i18n.py           生成 .strings
    python3 scripts/i18n.py --check   只检查（代码中的键是否都有翻译、是否有拼接字符串）

新增界面文字：代码里写 L("中文") / L("中文 %@", x)（SwiftUI 字面量自动本地化），
然后在下面的 T 表里加一行翻译。
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "Sources" / "ScreenshotPro"
OUT = ROOT / "Resources" / "Localization"

LANGS = ["en", "zh-Hant", "ja", "ko", "fr", "de", "es", "pt-BR", "ru"]

# key: (en, zh-Hant, ja, ko, fr, de, es, pt-BR, ru)
T = {
    # 标注工具
    "矩形": ("Rectangle", "矩形", "矩形", "사각형", "Rectangle", "Rechteck", "Rectángulo", "Retângulo", "Прямоугольник"),
    "椭圆": ("Ellipse", "橢圓", "楕円", "타원", "Ellipse", "Ellipse", "Elipse", "Elipse", "Эллипс"),
    "箭头": ("Arrow", "箭頭", "矢印", "화살표", "Flèche", "Pfeil", "Flecha", "Seta", "Стрелка"),
    "直线": ("Line", "直線", "直線", "직선", "Ligne", "Linie", "Línea", "Linha", "Линия"),
    "画笔": ("Pen", "畫筆", "ペン", "펜", "Crayon", "Stift", "Lápiz", "Caneta", "Перо"),
    "荧光笔": ("Highlighter", "螢光筆", "蛍光ペン", "형광펜", "Surligneur", "Textmarker", "Resaltador", "Marca-texto", "Маркер"),
    "文字": ("Text", "文字", "テキスト", "텍스트", "Texte", "Text", "Texto", "Texto", "Текст"),
    "马赛克": ("Pixelate", "馬賽克", "モザイク", "모자이크", "Pixeliser", "Verpixeln", "Pixelar", "Pixelizar", "Пикселизация"),
    "序号": ("Step", "序號", "番号", "번호", "Étape", "Schritt", "Paso", "Passo", "Шаг"),

    # 菜单
    "快捷键 %@ 注册失败，可能已被其他应用占用": (
        "Couldn't register shortcut %@. It may be used by another app.",
        "快速鍵 %@ 註冊失敗，可能已被其他 App 佔用",
        "ショートカット %@ を登録できません。他のアプリが使用している可能性があります",
        "단축키 %@ 를 등록할 수 없습니다. 다른 앱에서 사용 중일 수 있습니다",
        "Impossible d'enregistrer le raccourci %@. Il est peut-être utilisé par une autre app.",
        "Kurzbefehl %@ konnte nicht registriert werden. Er wird evtl. von einer anderen App verwendet.",
        "No se pudo registrar el atajo %@. Puede que otra app lo esté usando.",
        "Não foi possível registrar o atalho %@. Ele pode estar em uso por outro app.",
        "Не удалось назначить сочетание %@. Возможно, оно занято другим приложением."),
    "截图": ("Capture", "截圖", "スクリーンショット", "스크린샷", "Capture", "Bildschirmfoto", "Captura", "Captura", "Снимок экрана"),
    "长截图（滚动）": ("Scrolling Capture", "長截圖（捲動）", "スクロールキャプチャ", "스크롤 캡처", "Capture défilante", "Scrollende Aufnahme", "Captura con desplazamiento", "Captura com rolagem", "Снимок с прокруткой"),
    "文字识别（OCR）": ("Recognize Text (OCR)", "文字辨識（OCR）", "テキスト認識（OCR）", "텍스트 인식(OCR)", "Reconnaître le texte (OCR)", "Text erkennen (OCR)", "Reconocer texto (OCR)", "Reconhecer texto (OCR)", "Распознать текст (OCR)"),
    "延时 3 秒截图": ("Capture in 3 Seconds", "延遲 3 秒截圖", "3 秒後にキャプチャ", "3초 후 캡처", "Capture dans 3 secondes", "Aufnahme in 3 Sekunden", "Capturar en 3 segundos", "Capturar em 3 segundos", "Снимок через 3 секунды"),
    "3 秒后截图…": ("Capturing in 3 seconds…", "3 秒後截圖…", "3 秒後にキャプチャします…", "3초 후 캡처합니다…", "Capture dans 3 secondes…", "Aufnahme in 3 Sekunden …", "Capturando en 3 segundos…", "Capturando em 3 segundos…", "Снимок через 3 секунды…"),
    "最近截图": ("Recent Captures", "最近截圖", "最近のスクリーンショット", "최근 캡처", "Captures récentes", "Letzte Aufnahmen", "Capturas recientes", "Capturas recentes", "Недавние снимки"),
    "钉住剪贴板中的图片": ("Pin Image from Clipboard", "釘選剪貼簿中的圖片", "クリップボードの画像をピン留め", "클립보드 이미지 고정", "Épingler l'image du presse-papiers", "Bild aus Zwischenablage anheften", "Fijar imagen del portapapeles", "Fixar imagem da área de transferência", "Закрепить изображение из буфера"),
    "关闭所有钉图（%ld）": ("Close All Pins (%ld)", "關閉所有釘選圖片（%ld）", "すべてのピンを閉じる（%ld）", "모든 고정 이미지 닫기(%ld)", "Fermer toutes les épingles (%ld)", "Alle angehefteten Bilder schließen (%ld)", "Cerrar todas las fijadas (%ld)", "Fechar todas as fixadas (%ld)", "Закрыть все закреплённые (%ld)"),
    "设置…": ("Settings…", "設定…", "設定…", "설정…", "Réglages…", "Einstellungen …", "Ajustes…", "Ajustes…", "Настройки…"),
    "打开截图保存文件夹": ("Open Save Folder", "打開截圖儲存資料夾", "保存先フォルダを開く", "저장 폴더 열기", "Ouvrir le dossier d'enregistrement", "Speicherordner öffnen", "Abrir carpeta de guardado", "Abrir pasta de salvamento", "Открыть папку сохранения"),
    "⚠️ 授权屏幕录制…": ("⚠️ Grant Screen Recording Access…", "⚠️ 授權螢幕錄製…", "⚠️ 画面収録を許可…", "⚠️ 화면 기록 권한 허용…", "⚠️ Autoriser l'enregistrement de l'écran…", "⚠️ Bildschirmaufnahme erlauben …", "⚠️ Permitir grabación de pantalla…", "⚠️ Permitir gravação de tela…", "⚠️ Разрешить запись экрана…"),
    "重新启动": ("Relaunch", "重新啟動", "再起動", "다시 시작", "Relancer", "Neu starten", "Reiniciar", "Reiniciar", "Перезапустить"),
    "退出 Screenshot Pro": ("Quit Screenshot Pro", "結束 Screenshot Pro", "Screenshot Pro を終了", "Screenshot Pro 종료", "Quitter Screenshot Pro", "Screenshot Pro beenden", "Salir de Screenshot Pro", "Encerrar Screenshot Pro", "Завершить Screenshot Pro"),
    "暂无截图": ("No captures yet", "尚無截圖", "スクリーンショットはありません", "캡처 없음", "Aucune capture", "Noch keine Aufnahmen", "Aún no hay capturas", "Nenhuma captura ainda", "Снимков пока нет"),
    "单击钉到屏幕；按住 ⌥ 单击复制": ("Click to pin on screen; ⌥-click to copy", "按一下釘選到螢幕；按住 ⌥ 按一下拷貝", "クリックで画面にピン留め、⌥ クリックでコピー", "클릭하면 화면에 고정, ⌥ 클릭하면 복사", "Cliquez pour épingler ; ⌥-clic pour copier", "Klicken zum Anheften; ⌥-Klick zum Kopieren", "Haz clic para fijar; ⌥-clic para copiar", "Clique para fixar; ⌥-clique para copiar", "Щелчок — закрепить; ⌥-щелчок — скопировать"),
    "%@（复制）": ("%@ (Copy)", "%@（拷貝）", "%@（コピー）", "%@ (복사)", "%@ (copier)", "%@ (kopieren)", "%@ (copiar)", "%@ (copiar)", "%@ (копировать)"),
    "已复制到剪贴板": ("Copied to clipboard", "已拷貝到剪貼簿", "クリップボードにコピーしました", "클립보드에 복사됨", "Copié dans le presse-papiers", "In die Zwischenablage kopiert", "Copiado al portapapeles", "Copiado para a área de transferência", "Скопировано в буфер обмена"),
    "打开历史文件夹": ("Open History Folder", "打開歷史資料夾", "履歴フォルダを開く", "기록 폴더 열기", "Ouvrir le dossier d'historique", "Verlaufsordner öffnen", "Abrir carpeta del historial", "Abrir pasta do histórico", "Открыть папку истории"),
    "清空历史": ("Clear History", "清除歷史", "履歴を消去", "기록 지우기", "Effacer l'historique", "Verlauf löschen", "Borrar historial", "Limpar histórico", "Очистить историю"),
    "Screenshot Pro 设置": ("Screenshot Pro Settings", "Screenshot Pro 設定", "Screenshot Pro 設定", "Screenshot Pro 설정", "Réglages de Screenshot Pro", "Screenshot Pro – Einstellungen", "Ajustes de Screenshot Pro", "Ajustes do Screenshot Pro", "Настройки Screenshot Pro"),

    # 权限
    "需要「屏幕录制」权限": ("Screen Recording Permission Required", "需要「螢幕錄製」權限", "「画面収録」の許可が必要です", "‘화면 기록’ 권한이 필요합니다", "Autorisation « Enregistrement de l'écran » requise", "Berechtigung „Bildschirmaufnahme“ erforderlich", "Se necesita permiso de grabación de pantalla", "Permissão de gravação de tela necessária", "Требуется разрешение «Запись экрана»"),
    "Screenshot Pro 需要屏幕录制权限才能截图。\\n\\n请在「系统设置 → 隐私与安全性 → 屏幕与系统录音」中打开 Screenshot Pro，然后点「重新启动」。\\n\\n如果列表里已经开着但仍然无法截图（常见于重新编译后），先把它删掉（−）再重新添加。": (
        "Screenshot Pro needs Screen Recording permission to take screenshots.\\n\\nTurn on Screenshot Pro in System Settings → Privacy & Security → Screen & System Audio Recording, then click Relaunch.\\n\\nIf it is already on but capturing still fails (common after rebuilding), remove it (−) and add it again.",
        "Screenshot Pro 需要螢幕錄製權限才能截圖。\\n\\n請在「系統設定 → 隱私權與安全性 → 螢幕與系統錄音」中開啟 Screenshot Pro，然後按「重新啟動」。\\n\\n如果列表中已開啟但仍無法截圖（常見於重新編譯後），請先移除（−）再重新加入。",
        "スクリーンショットを撮るには画面収録の許可が必要です。\\n\\n「システム設定 → プライバシーとセキュリティ → 画面とシステムオーディオ収録」で Screenshot Pro をオンにしてから「再起動」をクリックしてください。\\n\\nすでにオンなのに撮影できない場合（再ビルド後によくあります）は、一度削除（−）してから追加し直してください。",
        "스크린샷을 찍으려면 화면 기록 권한이 필요합니다.\\n\\n시스템 설정 → 개인정보 보호 및 보안 → 화면 및 시스템 오디오 기록에서 Screenshot Pro를 켠 다음 ‘다시 시작’을 클릭하세요.\\n\\n이미 켜져 있는데도 캡처되지 않으면(다시 빌드한 후 흔함) 항목을 삭제(−)한 뒤 다시 추가하세요.",
        "Screenshot Pro a besoin de l'autorisation d'enregistrer l'écran pour faire des captures.\\n\\nActivez Screenshot Pro dans Réglages Système → Confidentialité et sécurité → Enregistrement de l'écran et de l'audio du système, puis cliquez sur Relancer.\\n\\nS'il est déjà activé mais que la capture échoue (fréquent après une recompilation), supprimez-le (−) puis ajoutez-le à nouveau.",
        "Screenshot Pro benötigt die Berechtigung zur Bildschirmaufnahme.\\n\\nAktiviere Screenshot Pro unter Systemeinstellungen → Datenschutz & Sicherheit → Bildschirm- & Systemaudioaufnahme und klicke dann auf „Neu starten“.\\n\\nFalls es bereits aktiviert ist, Aufnahmen aber fehlschlagen (häufig nach einem Neubau), entferne es (−) und füge es erneut hinzu.",
        "Screenshot Pro necesita permiso de grabación de pantalla para hacer capturas.\\n\\nActiva Screenshot Pro en Ajustes del Sistema → Privacidad y seguridad → Grabación de pantalla y audio del sistema y haz clic en Reiniciar.\\n\\nSi ya está activado pero no captura (habitual tras recompilar), elimínalo (−) y vuelve a añadirlo.",
        "O Screenshot Pro precisa da permissão de gravação de tela para fazer capturas.\\n\\nAtive o Screenshot Pro em Ajustes do Sistema → Privacidade e Segurança → Gravação de Tela e Áudio do Sistema e clique em Reiniciar.\\n\\nSe já estiver ativado mas a captura falhar (comum após recompilar), remova-o (−) e adicione-o novamente.",
        "Для снимков экрана Screenshot Pro нужно разрешение на запись экрана.\\n\\nВключите Screenshot Pro в Системных настройках → Конфиденциальность и безопасность → Запись экрана и системного звука, затем нажмите «Перезапустить».\\n\\nЕсли оно уже включено, но снимки не получаются (часто после пересборки), удалите приложение из списка (−) и добавьте снова."),
    "请在系统设置中允许屏幕录制，然后从菜单栏重新启动 Screenshot Pro": (
        "Allow Screen Recording in System Settings, then relaunch Screenshot Pro from the menu bar",
        "請在系統設定中允許螢幕錄製，然後從選單列重新啟動 Screenshot Pro",
        "システム設定で画面収録を許可してから、メニューバーで Screenshot Pro を再起動してください",
        "시스템 설정에서 화면 기록을 허용한 다음 메뉴 막대에서 Screenshot Pro를 다시 시작하세요",
        "Autorisez l'enregistrement de l'écran dans Réglages Système, puis relancez Screenshot Pro depuis la barre des menus",
        "Erlaube die Bildschirmaufnahme in den Systemeinstellungen und starte Screenshot Pro dann über die Menüleiste neu",
        "Permite la grabación de pantalla en Ajustes del Sistema y reinicia Screenshot Pro desde la barra de menús",
        "Permita a gravação de tela nos Ajustes do Sistema e reinicie o Screenshot Pro pela barra de menus",
        "Разрешите запись экрана в Системных настройках, затем перезапустите Screenshot Pro из строки меню"),
    "打开系统设置": ("Open System Settings", "打開系統設定", "システム設定を開く", "시스템 설정 열기", "Ouvrir Réglages Système", "Systemeinstellungen öffnen", "Abrir Ajustes del Sistema", "Abrir Ajustes do Sistema", "Открыть Системные настройки"),
    "稍后": ("Later", "稍後", "後で", "나중에", "Plus tard", "Später", "Más tarde", "Mais tarde", "Позже"),

    # 设置
    "复制到剪贴板": ("Copy to Clipboard", "拷貝到剪貼簿", "クリップボードにコピー", "클립보드에 복사", "Copier dans le presse-papiers", "In Zwischenablage kopieren", "Copiar al portapapeles", "Copiar para a área de transferência", "Копировать в буфер"),
    "保存到文件": ("Save to File", "儲存為檔案", "ファイルに保存", "파일로 저장", "Enregistrer dans un fichier", "Als Datei sichern", "Guardar en archivo", "Salvar em arquivo", "Сохранить в файл"),
    "复制并保存": ("Copy and Save", "拷貝並儲存", "コピーして保存", "복사 후 저장", "Copier et enregistrer", "Kopieren und sichern", "Copiar y guardar", "Copiar e salvar", "Копировать и сохранить"),
    "设置失败：%@（建议先把应用放到「应用程序」文件夹）": (
        "Failed: %@ (move the app to the Applications folder first)",
        "設定失敗：%@（建議先將 App 放到「應用程式」資料夾）",
        "設定に失敗しました：%@（先にアプリを「アプリケーション」フォルダに移動してください）",
        "설정 실패: %@ (먼저 앱을 응용 프로그램 폴더로 옮기세요)",
        "Échec : %@ (placez d'abord l'app dans le dossier Applications)",
        "Fehlgeschlagen: %@ (verschiebe die App zuerst in den Ordner „Programme“)",
        "Error: %@ (mueve primero la app a la carpeta Aplicaciones)",
        "Falhou: %@ (mova o app para a pasta Aplicativos primeiro)",
        "Ошибка: %@ (сначала переместите приложение в папку «Программы»)"),
    "通用": ("General", "一般", "一般", "일반", "Général", "Allgemein", "General", "Geral", "Основные"),
    "开机自动启动": ("Launch at Login", "登入時自動啟動", "ログイン時に起動", "로그인 시 실행", "Ouvrir à la connexion", "Beim Anmelden starten", "Abrir al iniciar sesión", "Abrir ao iniciar sessão", "Запускать при входе"),
    "快捷键": ("Shortcuts", "快速鍵", "ショートカット", "단축키", "Raccourcis", "Kurzbefehle", "Atajos", "Atalhos", "Сочетания клавиш"),
    "长截图": ("Scrolling Capture", "長截圖", "スクロールキャプチャ", "스크롤 캡처", "Capture défilante", "Scrollende Aufnahme", "Captura con desplazamiento", "Captura com rolagem", "Снимок с прокруткой"),
    "文字识别": ("Recognize Text", "文字辨識", "テキスト認識", "텍스트 인식", "Reconnaître le texte", "Text erkennen", "Reconocer texto", "Reconhecer texto", "Распознать текст"),
    "点击后按下新的组合键（至少包含 ⌘ ⌥ ⌃ 之一），按 Esc 取消。": (
        "Click, then press a new combination (must include ⌘, ⌥ or ⌃). Press Esc to cancel.",
        "按一下後按下新的組合鍵（至少包含 ⌘ ⌥ ⌃ 其中之一），按 Esc 取消。",
        "クリックして新しい組み合わせを押してください（⌘ ⌥ ⌃ のいずれかを含む）。Esc でキャンセル。",
        "클릭한 후 새 조합을 누르세요(⌘ ⌥ ⌃ 중 하나 포함). Esc로 취소.",
        "Cliquez puis appuyez sur une nouvelle combinaison (avec ⌘, ⌥ ou ⌃). Échap pour annuler.",
        "Klicken und neue Tastenkombination drücken (mit ⌘, ⌥ oder ⌃). Esc bricht ab.",
        "Haz clic y pulsa una nueva combinación (con ⌘, ⌥ o ⌃). Esc para cancelar.",
        "Clique e pressione uma nova combinação (com ⌘, ⌥ ou ⌃). Esc para cancelar.",
        "Щёлкните и нажмите новое сочетание (с ⌘, ⌥ или ⌃). Esc — отмена."),
    "输出": ("Output", "輸出", "出力", "출력", "Sortie", "Ausgabe", "Salida", "Saída", "Вывод"),
    "完成截图后（↩ / 双击）": ("When done (↩ / double-click)", "完成截圖後（↩ / 按兩下）", "完了時（↩ / ダブルクリック）", "완료 시(↩ / 이중 클릭)", "Une fois terminé (↩ / double-clic)", "Nach Abschluss (↩ / Doppelklick)", "Al terminar (↩ / doble clic)", "Ao concluir (↩ / clique duplo)", "По завершении (↩ / двойной щелчок)"),
    "图片格式": ("Image Format", "圖片格式", "画像フォーマット", "이미지 포맷", "Format d'image", "Bildformat", "Formato de imagen", "Formato de imagem", "Формат изображения"),
    "按 Retina 原始分辨率导出（关闭则导出 1x）": ("Export at full Retina resolution (off = 1x)", "以 Retina 原始解析度輸出（關閉則輸出 1x）", "Retina の元の解像度で書き出す（オフで 1x）", "Retina 원본 해상도로 내보내기(끄면 1x)", "Exporter en résolution Retina (désactivé = 1x)", "In voller Retina-Auflösung exportieren (aus = 1x)", "Exportar a resolución Retina completa (desactivado = 1x)", "Exportar na resolução Retina total (desativado = 1x)", "Экспорт в полном разрешении Retina (выкл. = 1x)"),
    "保存位置": ("Save Location", "儲存位置", "保存先", "저장 위치", "Emplacement", "Speicherort", "Ubicación", "Local de salvamento", "Папка сохранения"),
    "选择…": ("Choose…", "選擇…", "選択…", "선택…", "Choisir…", "Auswählen …", "Elegir…", "Escolher…", "Выбрать…"),
    "独立窗口截图包含阴影": ("Include shadow in window captures", "獨立視窗截圖包含陰影", "ウインドウのキャプチャに影を含める", "윈도우 캡처에 그림자 포함", "Inclure l'ombre des fenêtres", "Fensterschatten einbeziehen", "Incluir sombra en capturas de ventana", "Incluir sombra nas capturas de janela", "Включать тень окна"),
    "显示放大镜与取色": ("Show magnifier and color picker", "顯示放大鏡與取色", "拡大鏡とカラーピッカーを表示", "돋보기와 색상 선택기 표시", "Afficher la loupe et la pipette", "Lupe und Farbpipette anzeigen", "Mostrar lupa y cuentagotas", "Mostrar lupa e conta-gotas", "Показывать лупу и пипетку"),
    "截图中包含鼠标指针": ("Include mouse pointer", "截圖包含滑鼠指標", "マウスポインタを含める", "마우스 포인터 포함", "Inclure le pointeur", "Mauszeiger einbeziehen", "Incluir puntero del ratón", "Incluir ponteiro do mouse", "Включать указатель мыши"),
    "播放快门声": ("Play shutter sound", "播放快門聲", "シャッター音を鳴らす", "셔터 소리 재생", "Son d'obturateur", "Auslöserton abspielen", "Reproducir sonido de obturador", "Reproduzir som do obturador", "Звук затвора"),

    # 操作提示
    "选区": ("Selection", "選取範圍", "選択範囲", "선택 영역", "Sélection", "Auswahl", "Selección", "Seleção", "Выделение"),
    "框选区域": ("Select an area", "框選區域", "範囲を選択", "영역 선택", "Sélectionner une zone", "Bereich auswählen", "Seleccionar un área", "Selecionar uma área", "Выделить область"),
    "拖拽": ("Drag", "拖移", "ドラッグ", "드래그", "Glisser", "Ziehen", "Arrastrar", "Arrastar", "Перетащить"),
    "选中窗口": ("Select a window", "選取視窗", "ウインドウを選択", "윈도우 선택", "Sélectionner une fenêtre", "Fenster auswählen", "Seleccionar una ventana", "Selecionar uma janela", "Выбрать окно"),
    "单击": ("Click", "按一下", "クリック", "클릭", "Clic", "Klick", "Clic", "Clique", "Щелчок"),
    "截取独立窗口（带阴影）": ("Capture a single window (with shadow)", "截取獨立視窗（含陰影）", "ウインドウ単体をキャプチャ（影付き）", "단일 윈도우 캡처(그림자 포함)", "Capturer une fenêtre (avec ombre)", "Einzelnes Fenster aufnehmen (mit Schatten)", "Capturar una ventana (con sombra)", "Capturar uma janela (com sombra)", "Снимок одного окна (с тенью)"),
    "+ 单击": ("+ Click", "+ 按一下", "+ クリック", "+ 클릭", "+ clic", "+ Klick", "+ clic", "+ clique", "+ щелчок"),
    "多选窗口并合成": ("Combine several windows", "多選視窗並合成", "複数ウインドウを合成", "여러 윈도우 합치기", "Combiner plusieurs fenêtres", "Mehrere Fenster kombinieren", "Combinar varias ventanas", "Combinar várias janelas", "Объединить несколько окон"),
    "+ 单击，再按": ("+ Click, then", "+ 按一下，再按", "+ クリック、続けて", "+ 클릭 후", "+ clic, puis", "+ Klick, dann", "+ clic y luego", "+ clique e depois", "+ щелчок, затем"),
    "复制颜色 HEX / RGB": ("Copy color HEX / RGB", "拷貝顏色 HEX / RGB", "色をコピー HEX / RGB", "색상 복사 HEX / RGB", "Copier la couleur HEX / RGB", "Farbe kopieren HEX / RGB", "Copiar color HEX / RGB", "Copiar cor HEX / RGB", "Копировать цвет HEX / RGB"),
    "微调位置": ("Nudge", "微調位置", "位置を微調整", "위치 미세 조정", "Ajuster la position", "Position feinjustieren", "Ajuste fino", "Ajuste fino", "Точная подгонка"),
    "加": ("with", "加", "＋", "+", "avec", "mit", "con", "com", "с"),
    "每次 10pt": ("for 10 pt", "每次 10pt", "で 10pt", "10pt씩", "pour 10 pt", "für 10 pt", "para 10 pt", "para 10 pt", "на 10 pt"),
    "标注工具": ("Annotation Tools", "標註工具", "注釈ツール", "주석 도구", "Outils d'annotation", "Anmerkungswerkzeuge", "Herramientas de anotación", "Ferramentas de anotação", "Инструменты разметки"),
    "画正方形 / 锁定 45°": ("Square shape / snap to 45°", "畫正方形 / 鎖定 45°", "正方形 / 45° に固定", "정사각형 / 45° 고정", "Carré / angle de 45°", "Quadrat / 45° einrasten", "Cuadrado / ajustar a 45°", "Quadrado / travar em 45°", "Квадрат / шаг 45°"),
    "按住": ("Hold", "按住", "押したまま", "누른 상태", "Maintenir", "Halten", "Mantén", "Segure", "Удерживать"),
    "编辑已有文字": ("Edit existing text", "編輯已有文字", "既存のテキストを編集", "기존 텍스트 편집", "Modifier un texte", "Text bearbeiten", "Editar texto existente", "Editar texto existente", "Изменить текст"),
    "双击文字": ("Double-click text", "按兩下文字", "テキストをダブルクリック", "텍스트 이중 클릭", "Double-clic sur le texte", "Doppelklick auf Text", "Doble clic en el texto", "Clique duplo no texto", "Двойной щелчок по тексту"),
    "完成与编辑": ("Finish & Edit", "完成與編輯", "完了と編集", "완료 및 편집", "Terminer et modifier", "Abschließen & Bearbeiten", "Terminar y editar", "Concluir e editar", "Завершение и правка"),
    "完成（执行默认动作）": ("Finish (default action)", "完成（執行預設動作）", "完了（既定の動作）", "완료(기본 동작)", "Terminer (action par défaut)", "Abschließen (Standardaktion)", "Terminar (acción predeterminada)", "Concluir (ação padrão)", "Готово (действие по умолчанию)"),
    "或在选区内双击": ("or double-click the selection", "或在選取範圍內按兩下", "または選択範囲をダブルクリック", "또는 선택 영역 이중 클릭", "ou double-clic dans la sélection", "oder Doppelklick in die Auswahl", "o doble clic en la selección", "ou clique duplo na seleção", "или двойной щелчок по выделению"),
    "复制 / 保存": ("Copy / Save", "拷貝 / 儲存", "コピー / 保存", "복사 / 저장", "Copier / Enregistrer", "Kopieren / Sichern", "Copiar / Guardar", "Copiar / Salvar", "Копировать / Сохранить"),
    "撤销 / 重做": ("Undo / Redo", "還原 / 重做", "取り消す / やり直す", "실행 취소 / 실행 복귀", "Annuler / Rétablir", "Widerrufen / Wiederholen", "Deshacer / Rehacer", "Desfazer / Refazer", "Отменить / Повторить"),
    "删除选中标注": ("Delete selected annotation", "刪除選取的標註", "選択した注釈を削除", "선택한 주석 삭제", "Supprimer l'annotation", "Ausgewählte Anmerkung löschen", "Eliminar anotación seleccionada", "Excluir anotação selecionada", "Удалить выбранную пометку"),
    "重新选区 / 退出": ("Reselect / Quit", "重新選取 / 結束", "選択し直す / 終了", "다시 선택 / 종료", "Resélectionner / Quitter", "Neu auswählen / Beenden", "Volver a seleccionar / Salir", "Selecionar de novo / Sair", "Выделить заново / Выйти"),
    "右键": ("Right-click", "按右鍵", "右クリック", "오른쪽 클릭", "Clic droit", "Rechtsklick", "Clic derecho", "Clique direito", "Правый щелчок"),
    "钉图": ("Pinned Images", "釘選圖片", "ピン留め画像", "고정 이미지", "Images épinglées", "Angeheftete Bilder", "Imágenes fijadas", "Imagens fixadas", "Закреплённые изображения"),
    "缩放": ("Zoom", "縮放", "拡大・縮小", "확대/축소", "Zoom", "Zoomen", "Zoom", "Zoom", "Масштаб"),
    "滚轮": ("Scroll", "滾輪", "スクロール", "스크롤", "Molette", "Scrollen", "Rueda", "Rolagem", "Колесо"),
    "原始大小": ("Actual Size", "原始大小", "実際のサイズ", "실제 크기", "Taille réelle", "Originalgröße", "Tamaño real", "Tamanho real", "Исходный размер"),
    "透明度": ("Opacity", "透明度", "不透明度", "불투명도", "Opacité", "Deckkraft", "Opacidad", "Opacidade", "Непрозрачность"),
    "关闭": ("Close", "關閉", "閉じる", "닫기", "Fermer", "Schließen", "Cerrar", "Fechar", "Закрыть"),
    "双击": ("Double-click", "按兩下", "ダブルクリック", "이중 클릭", "Double-clic", "Doppelklick", "Doble clic", "Clique duplo", "Двойной щелчок"),
    "请按下快捷键…": ("Press shortcut…", "請按下快速鍵…", "キーを押してください…", "단축키를 누르세요…", "Appuyez sur un raccourci…", "Kurzbefehl drücken …", "Pulsa el atajo…", "Pressione o atalho…", "Нажмите сочетание…"),
    "未设置": ("Not set", "未設定", "未設定", "설정 안 됨", "Non défini", "Nicht festgelegt", "Sin definir", "Não definido", "Не задано"),

    # 截图遮罩
    "截图失败：%@": ("Capture failed: %@", "截圖失敗：%@", "キャプチャに失敗しました：%@", "캡처 실패: %@", "Échec de la capture : %@", "Aufnahme fehlgeschlagen: %@", "Error al capturar: %@", "Falha na captura: %@", "Не удалось сделать снимок: %@"),
    "拖拽框选 · 单击选择窗口 · ⌥单击截取独立窗口 · ⌘单击多选窗口 · Esc 退出": (
        "Drag to select · Click a window · ⌥-click: single window · ⌘-click: multiple windows · Esc to quit",
        "拖移框選 · 按一下選取視窗 · ⌥ 按一下截取獨立視窗 · ⌘ 按一下多選視窗 · Esc 結束",
        "ドラッグで範囲選択 · クリックでウインドウ · ⌥クリックで単体 · ⌘クリックで複数選択 · Esc で終了",
        "드래그로 영역 선택 · 클릭으로 윈도우 선택 · ⌥ 클릭: 단일 윈도우 · ⌘ 클릭: 여러 윈도우 · Esc 종료",
        "Glisser pour sélectionner · Clic : fenêtre · ⌥-clic : fenêtre seule · ⌘-clic : plusieurs · Échap pour quitter",
        "Ziehen zum Auswählen · Klick: Fenster · ⌥-Klick: Einzelfenster · ⌘-Klick: mehrere · Esc beendet",
        "Arrastra para seleccionar · Clic: ventana · ⌥-clic: ventana sola · ⌘-clic: varias · Esc para salir",
        "Arraste para selecionar · Clique: janela · ⌥-clique: janela única · ⌘-clique: várias · Esc para sair",
        "Перетащите для выделения · Щелчок: окно · ⌥-щелчок: одно окно · ⌘-щелчок: несколько · Esc — выход"),
    "已选 %ld 个窗口 · 继续 ⌘单击添加 · ↩ 合成截图 · Esc 取消": (
        "%ld windows selected · ⌘-click to add more · ↩ to combine · Esc to cancel",
        "已選 %ld 個視窗 · 繼續 ⌘ 按一下加入 · ↩ 合成截圖 · Esc 取消",
        "%ld 個のウインドウを選択中 · ⌘クリックで追加 · ↩ で合成 · Esc でキャンセル",
        "윈도우 %ld개 선택됨 · ⌘ 클릭으로 추가 · ↩ 합치기 · Esc 취소",
        "%ld fenêtres sélectionnées · ⌘-clic pour ajouter · ↩ pour combiner · Échap pour annuler",
        "%ld Fenster ausgewählt · ⌘-Klick zum Hinzufügen · ↩ zum Kombinieren · Esc bricht ab",
        "%ld ventanas seleccionadas · ⌘-clic para añadir · ↩ para combinar · Esc para cancelar",
        "%ld janelas selecionadas · ⌘-clique para adicionar · ↩ para combinar · Esc para cancelar",
        "Выбрано окон: %ld · ⌘-щелчок — добавить · ↩ — объединить · Esc — отмена"),
    "C 复制 · ⇧C RGB": ("C copy · ⇧C RGB", "C 拷貝 · ⇧C RGB", "C コピー · ⇧C RGB", "C 복사 · ⇧C RGB", "C copier · ⇧C RGB", "C kopieren · ⇧C RGB", "C copiar · ⇧C RGB", "C copiar · ⇧C RGB", "C копир. · ⇧C RGB"),
    "窗口截图失败：%@": ("Window capture failed: %@", "視窗截圖失敗：%@", "ウインドウのキャプチャに失敗しました：%@", "윈도우 캡처 실패: %@", "Échec de la capture de fenêtre : %@", "Fensteraufnahme fehlgeschlagen: %@", "Error al capturar la ventana: %@", "Falha ao capturar a janela: %@", "Не удалось снять окно: %@"),
    "多窗口截图失败：%@": ("Multi-window capture failed: %@", "多視窗截圖失敗：%@", "複数ウインドウのキャプチャに失敗しました：%@", "여러 윈도우 캡처 실패: %@", "Échec de la capture multi-fenêtres : %@", "Mehrfenster-Aufnahme fehlgeschlagen: %@", "Error al capturar varias ventanas: %@", "Falha ao capturar várias janelas: %@", "Не удалось снять несколько окон: %@"),
    "已复制颜色 %@": ("Copied color %@", "已拷貝顏色 %@", "色 %@ をコピーしました", "색상 %@ 복사됨", "Couleur %@ copiée", "Farbe %@ kopiert", "Color %@ copiado", "Cor %@ copiada", "Цвет %@ скопирован"),
    "输入文字": ("Type text", "輸入文字", "テキストを入力", "텍스트 입력", "Saisir du texte", "Text eingeben", "Escribe texto", "Digite o texto", "Введите текст"),
    "找不到显示器": ("Display not found", "找不到顯示器", "ディスプレイが見つかりません", "디스플레이를 찾을 수 없음", "Écran introuvable", "Bildschirm nicht gefunden", "No se encontró la pantalla", "Tela não encontrada", "Дисплей не найден"),
    "找不到该窗口": ("Window not found", "找不到該視窗", "ウインドウが見つかりません", "윈도우를 찾을 수 없음", "Fenêtre introuvable", "Fenster nicht gefunden", "No se encontró la ventana", "Janela não encontrada", "Окно не найдено"),

    # 工具栏
    "撤销（⌘Z）": ("Undo (⌘Z)", "還原（⌘Z）", "取り消す（⌘Z）", "실행 취소(⌘Z)", "Annuler (⌘Z)", "Widerrufen (⌘Z)", "Deshacer (⌘Z)", "Desfazer (⌘Z)", "Отменить (⌘Z)"),
    "重做（⇧⌘Z）": ("Redo (⇧⌘Z)", "重做（⇧⌘Z）", "やり直す（⇧⌘Z）", "실행 복귀(⇧⌘Z)", "Rétablir (⇧⌘Z)", "Wiederholen (⇧⌘Z)", "Rehacer (⇧⌘Z)", "Refazer (⇧⌘Z)", "Повторить (⇧⌘Z)"),
    "识别文字（OCR）": ("Recognize Text (OCR)", "辨識文字（OCR）", "テキスト認識（OCR）", "텍스트 인식(OCR)", "Reconnaître le texte (OCR)", "Text erkennen (OCR)", "Reconocer texto (OCR)", "Reconhecer texto (OCR)", "Распознать текст (OCR)"),
    "长截图（滚动截图）": ("Scrolling Capture", "長截圖（捲動截圖）", "スクロールキャプチャ", "스크롤 캡처", "Capture défilante", "Scrollende Aufnahme", "Captura con desplazamiento", "Captura com rolagem", "Снимок с прокруткой"),
    "钉在屏幕上": ("Pin to Screen", "釘選在螢幕上", "画面にピン留め", "화면에 고정", "Épingler à l'écran", "Auf Bildschirm anheften", "Fijar en pantalla", "Fixar na tela", "Закрепить на экране"),
    "保存（⌘S）": ("Save (⌘S)", "儲存（⌘S）", "保存（⌘S）", "저장(⌘S)", "Enregistrer (⌘S)", "Sichern (⌘S)", "Guardar (⌘S)", "Salvar (⌘S)", "Сохранить (⌘S)"),
    "取消（Esc）": ("Cancel (Esc)", "取消（Esc）", "キャンセル（Esc）", "취소(Esc)", "Annuler (Échap)", "Abbrechen (Esc)", "Cancelar (Esc)", "Cancelar (Esc)", "Отмена (Esc)"),
    "完成（↩）": ("Done (↩)", "完成（↩）", "完了（↩）", "완료(↩)", "Terminé (↩)", "Fertig (↩)", "Listo (↩)", "Concluir (↩)", "Готово (↩)"),
    "颜色": ("Color", "顏色", "色", "색상", "Couleur", "Farbe", "Color", "Cor", "Цвет"),
    "字号": ("Font size", "字級", "文字サイズ", "글자 크기", "Taille du texte", "Schriftgröße", "Tamaño de letra", "Tamanho da fonte", "Размер шрифта"),
    "大小": ("Size", "大小", "サイズ", "크기", "Taille", "Größe", "Tamaño", "Tamanho", "Размер"),
    "粗细": ("Thickness", "粗細", "太さ", "굵기", "Épaisseur", "Stärke", "Grosor", "Espessura", "Толщина"),
    "实心填充": ("Fill", "實心填滿", "塗りつぶし", "채우기", "Remplir", "Füllen", "Relleno", "Preencher", "Заливка"),
    "方形马赛克（可拖动、调整大小）": ("Rectangle pixelate (movable, resizable)", "方形馬賽克（可拖移、調整大小）", "矩形モザイク（移動・サイズ変更可）", "사각형 모자이크(이동·크기 조절 가능)", "Pixelisation rectangulaire (déplaçable, redimensionnable)", "Rechteckig verpixeln (verschieb- und skalierbar)", "Pixelado rectangular (movible y redimensionable)", "Pixelização retangular (móvel e redimensionável)", "Прямоугольная пикселизация (можно двигать и менять размер)"),
    "涂抹马赛克": ("Brush pixelate", "塗抹馬賽克", "ブラシでモザイク", "브러시 모자이크", "Pixeliser au pinceau", "Mit Pinsel verpixeln", "Pixelar con pincel", "Pixelizar com pincel", "Пикселизация кистью"),

    # OCR
    "正在识别文字…": ("Recognizing text…", "正在辨識文字…", "テキストを認識中…", "텍스트 인식 중…", "Reconnaissance du texte…", "Text wird erkannt …", "Reconociendo texto…", "Reconhecendo texto…", "Распознавание текста…"),
    "没有识别到文字": ("No text found", "未辨識到文字", "テキストが見つかりません", "텍스트를 찾을 수 없음", "Aucun texte trouvé", "Kein Text gefunden", "No se encontró texto", "Nenhum texto encontrado", "Текст не найден"),
    "已复制识别结果（%ld 行）": ("Copied recognized text (%ld lines)", "已拷貝辨識結果（%ld 行）", "認識結果をコピーしました（%ld 行）", "인식 결과 복사됨(%ld줄)", "Texte reconnu copié (%ld lignes)", "Erkannter Text kopiert (%ld Zeilen)", "Texto reconocido copiado (%ld líneas)", "Texto reconhecido copiado (%ld linhas)", "Распознанный текст скопирован (строк: %ld)"),
    "识别失败：%@": ("Recognition failed: %@", "辨識失敗：%@", "認識に失敗しました：%@", "인식 실패: %@", "Échec de la reconnaissance : %@", "Erkennung fehlgeschlagen: %@", "Error de reconocimiento: %@", "Falha no reconhecimento: %@", "Ошибка распознавания: %@"),
    "识别结果（已复制到剪贴板）": ("Recognized Text (copied to clipboard)", "辨識結果（已拷貝到剪貼簿）", "認識結果（クリップボードにコピー済み）", "인식 결과(클립보드에 복사됨)", "Texte reconnu (copié)", "Erkannter Text (kopiert)", "Texto reconocido (copiado)", "Texto reconhecido (copiado)", "Распознанный текст (скопирован)"),
    "复制全部": ("Copy All", "全部拷貝", "すべてコピー", "모두 복사", "Tout copier", "Alles kopieren", "Copiar todo", "Copiar tudo", "Копировать всё"),
    "已复制": ("Copied", "已拷貝", "コピーしました", "복사됨", "Copié", "Kopiert", "Copiado", "Copiado", "Скопировано"),

    # 钉图
    "已钉在屏幕上：滚轮缩放 · 1–9/0 透明度 · 双击或 Esc 关闭": (
        "Pinned: scroll to zoom · 1–9/0 opacity · double-click or Esc to close",
        "已釘選在螢幕上：滾輪縮放 · 1–9/0 透明度 · 按兩下或 Esc 關閉",
        "ピン留めしました：スクロールで拡大縮小 · 1–9/0 で不透明度 · ダブルクリックか Esc で閉じる",
        "고정됨: 스크롤로 확대/축소 · 1–9/0 불투명도 · 이중 클릭 또는 Esc로 닫기",
        "Épinglé : molette pour zoomer · 1–9/0 opacité · double-clic ou Échap pour fermer",
        "Angeheftet: Scrollen zum Zoomen · 1–9/0 Deckkraft · Doppelklick oder Esc schließt",
        "Fijado: rueda para zoom · 1–9/0 opacidad · doble clic o Esc para cerrar",
        "Fixado: role para zoom · 1–9/0 opacidade · clique duplo ou Esc para fechar",
        "Закреплено: колесо — масштаб · 1–9/0 — прозрачность · двойной щелчок или Esc — закрыть"),
    "剪贴板里没有图片": ("No image on the clipboard", "剪貼簿中沒有圖片", "クリップボードに画像がありません", "클립보드에 이미지가 없음", "Aucune image dans le presse-papiers", "Kein Bild in der Zwischenablage", "No hay ninguna imagen en el portapapeles", "Nenhuma imagem na área de transferência", "В буфере нет изображения"),
    "复制": ("Copy", "拷貝", "コピー", "복사", "Copier", "Kopieren", "Copiar", "Copiar", "Копировать"),
    "另存为…": ("Save As…", "另存新檔…", "別名で保存…", "다른 이름으로 저장…", "Enregistrer sous…", "Sichern unter …", "Guardar como…", "Salvar como…", "Сохранить как…"),
    "关闭所有钉图": ("Close All Pins", "關閉所有釘選圖片", "すべてのピンを閉じる", "모든 고정 이미지 닫기", "Fermer toutes les épingles", "Alle angehefteten Bilder schließen", "Cerrar todas las fijadas", "Fechar todas as fixadas", "Закрыть все закреплённые"),

    # 长截图
    "请滚动选区内的内容（向下）…": ("Scroll the content down…", "請捲動選取範圍內的內容（向下）…", "選択範囲の内容を下へスクロールしてください…", "선택 영역의 내용을 아래로 스크롤하세요…", "Faites défiler le contenu vers le bas…", "Inhalt nach unten scrollen …", "Desplaza el contenido hacia abajo…", "Role o conteúdo para baixo…", "Прокрутите содержимое вниз…"),
    "取消": ("Cancel", "取消", "キャンセル", "취소", "Annuler", "Abbrechen", "Cancelar", "Cancelar", "Отмена"),
    "完成": ("Done", "完成", "完了", "완료", "Terminé", "Fertig", "Listo", "Concluir", "Готово"),
    "⚠️ 滚动太快，请慢一点 · 已拼接 %ld px": ("⚠️ Too fast — scroll slower · %ld px stitched", "⚠️ 捲動太快，請慢一點 · 已拼接 %ld px", "⚠️ 速すぎます。ゆっくり · %ld px 結合済み", "⚠️ 너무 빠릅니다. 천천히 · %ld px 연결됨", "⚠️ Trop rapide, ralentissez · %ld px assemblés", "⚠️ Zu schnell – langsamer scrollen · %ld px", "⚠️ Demasiado rápido · %ld px unidos", "⚠️ Rápido demais · %ld px unidos", "⚠️ Слишком быстро · склеено %ld px"),
    "已拼接 %ld px · %ld 帧": ("%ld px stitched · %ld frames", "已拼接 %ld px · %ld 幀", "%ld px 結合済み · %ld フレーム", "%ld px 연결됨 · %ld프레임", "%ld px assemblés · %ld images", "%ld px zusammengesetzt · %ld Bilder", "%ld px unidos · %ld fotogramas", "%ld px unidos · %ld quadros", "Склеено %ld px · кадров: %ld"),
    "已达到最大长度": ("Maximum length reached", "已達最大長度", "最大の長さに達しました", "최대 길이에 도달함", "Longueur maximale atteinte", "Maximale Länge erreicht", "Se alcanzó la longitud máxima", "Comprimento máximo atingido", "Достигнута максимальная длина"),
    "长截图失败：%@": ("Scrolling capture failed: %@", "長截圖失敗：%@", "スクロールキャプチャに失敗しました：%@", "스크롤 캡처 실패: %@", "Échec de la capture défilante : %@", "Scrollende Aufnahme fehlgeschlagen: %@", "Error en la captura con desplazamiento: %@", "Falha na captura com rolagem: %@", "Ошибка снимка с прокруткой: %@"),
    "正在拼接…": ("Stitching…", "正在拼接…", "結合中…", "연결 중…", "Assemblage…", "Wird zusammengesetzt …", "Uniendo…", "Unindo…", "Склейка…"),
    "没有截取到内容": ("Nothing was captured", "沒有截取到內容", "何もキャプチャされませんでした", "캡처된 내용 없음", "Rien n'a été capturé", "Nichts aufgenommen", "No se capturó nada", "Nada foi capturado", "Ничего не снято"),

    # 输出
    "已复制到剪贴板（%ld × %ld）": ("Copied to clipboard (%ld × %ld)", "已拷貝到剪貼簿（%ld × %ld）", "クリップボードにコピーしました（%ld × %ld）", "클립보드에 복사됨(%ld × %ld)", "Copié dans le presse-papiers (%ld × %ld)", "In die Zwischenablage kopiert (%ld × %ld)", "Copiado al portapapeles (%ld × %ld)", "Copiado para a área de transferência (%ld × %ld)", "Скопировано в буфер (%ld × %ld)"),
    "已保存：%@": ("Saved: %@", "已儲存：%@", "保存しました：%@", "저장됨: %@", "Enregistré : %@", "Gesichert: %@", "Guardado: %@", "Salvo: %@", "Сохранено: %@"),
    "已复制并保存：%@": ("Copied and saved: %@", "已拷貝並儲存：%@", "コピーして保存しました：%@", "복사 및 저장됨: %@", "Copié et enregistré : %@", "Kopiert und gesichert: %@", "Copiado y guardado: %@", "Copiado e salvo: %@", "Скопировано и сохранено: %@"),
    "截图 %@": ("Screenshot %@", "截圖 %@", "スクリーンショット %@", "스크린샷 %@", "Capture %@", "Bildschirmfoto %@", "Captura %@", "Captura %@", "Снимок экрана %@"),
    "编码失败": ("Encoding failed", "編碼失敗", "エンコードに失敗しました", "인코딩 실패", "Échec de l'encodage", "Kodierung fehlgeschlagen", "Error de codificación", "Falha na codificação", "Ошибка кодирования"),
    "保存失败：%@": ("Save failed: %@", "儲存失敗：%@", "保存に失敗しました：%@", "저장 실패: %@", "Échec de l'enregistrement : %@", "Sichern fehlgeschlagen: %@", "Error al guardar: %@", "Falha ao salvar: %@", "Не удалось сохранить: %@"),
}


def source_keys():
    """代码中所有含中文的字符串字面量（SelfTest 与注释除外）"""
    keys, problems = [], []
    for p in sorted(SRC.rglob("*.swift")):
        if p.name == "SelfTest.swift":
            continue
        for n, line in enumerate(p.read_text().splitlines(), 1):
            if line.strip().startswith("//") or line.strip().startswith("///"):
                continue
            for m in re.finditer(r'"((?:[^"\\]|\\.)*)"', line):
                s = m.group(1)
                if not re.search(r"[一-鿿]", s):
                    continue
                if "\\(" in s:
                    problems.append(f"{p.relative_to(ROOT)}:{n}: 字符串插值无法翻译，请改用 L(\"…%@\", x)：{s}")
                if s not in keys:
                    keys.append(s)
    return keys, problems


def escape(s):
    return s.replace('"', '\\"')


def main():
    keys, problems = source_keys()
    missing = [k for k in keys if k not in T]
    unused = [k for k in T if k not in keys]
    bad = [k for k, v in T.items() if len(v) != len(LANGS)]
    fmt = [k for k, v in T.items() for t in v if sorted(re.findall(r"%l?[d@]", k)) != sorted(re.findall(r"%l?[d@]", t))]
    for p in problems:
        print("❌", p)
    for k in missing:
        print("❌ 缺少翻译：", k)
    for k in bad:
        print("❌ 翻译数量不对：", k)
    for k in sorted(set(fmt)):
        print("❌ 占位符不一致：", k)
    for k in unused:
        print("⚠️  未使用的翻译：", k)
    if problems or missing or bad or fmt:
        sys.exit(1)
    if "--check" in sys.argv:
        print(f"✅ {len(keys)} 条文字 × {len(LANGS) + 1} 种语言，全部覆盖")
        return

    header = "/* 由 scripts/i18n.py 生成，请勿手动修改 */\n\n"
    for i, lang in enumerate(LANGS):
        d = OUT / f"{lang}.lproj"
        d.mkdir(parents=True, exist_ok=True)
        lines = [f'"{escape(k)}" = "{escape(T[k][i])}";' for k in keys]
        (d / "Localizable.strings").write_text(header + "\n".join(lines) + "\n")
    # 简体中文：键即原文
    d = OUT / "zh-Hans.lproj"
    d.mkdir(parents=True, exist_ok=True)
    (d / "Localizable.strings").write_text(header + "\n".join(f'"{escape(k)}" = "{escape(k)}";' for k in keys) + "\n")
    print(f"✅ 已生成 {len(LANGS) + 1} 种语言，每种 {len(keys)} 条 → {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
