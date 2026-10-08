// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

/// Shared labels for discovery controls. Walkthrough samples are fictional.
struct SettingsDiscoveryStrings {
    let simple: String
    let advanced: String
    let expert: String
    let capture: String
    let applications: String
    let preview: String
    let included: String
    let configure: String
    private let controls: [String]

    enum Control: Int, CaseIterable {
        case show, visibility, hidden, shown, hiddenBy, filterHelp, searchVisible, category, allCategories
        case includedOnly, includedFirst, undoBulk, notIncluded, parentRequired, behaviorOff, behaviorOn, onDemand
        case turnOn, includeHelp, closePreview, illustration, noPermissions, pause, play
    }

    func text(_ control: Control) -> String { controls[control.rawValue] }

    func name(_ level: SettingsExperience) -> String {
        switch level {
        case .simple: return simple
        case .advanced: return advanced
        case .expert: return expert
        }
    }

    static func localized(_ language: AppLanguage) -> Self {
        let words: [String]
        switch language {
        case .enUS: words = ["Focused", "Expanded", "Everything", "Capture & media", "Apps & maintenance", "Preview", "Included in app", "Configure"]
        case .ptBR: words = ["Focado", "Ampliado", "Tudo", "Captura e mídia", "Apps e manutenção", "Prévia", "Incluído no app", "Configurar"]
        case .es: words = ["Enfocado", "Ampliado", "Todo", "Captura y medios", "Apps y mantenimiento", "Vista previa", "Incluido en la app", "Configurar"]
        case .sk: words = ["Zamerané", "Rozšírené", "Všetko", "Zachytávanie a médiá", "Aplikácie a údržba", "Ukážka", "Zahrnuté v aplikácii", "Nastaviť"]
        case .de: words = ["Fokussiert", "Erweitert", "Alles", "Aufnahme & Medien", "Apps & Wartung", "Vorschau", "In App enthalten", "Konfigurieren"]
        case .fr: words = ["Ciblé", "Étendu", "Tout", "Capture et médias", "Apps et maintenance", "Aperçu", "Inclus dans l’app", "Configurer"]
        case .it: words = ["Mirato", "Esteso", "Tutto", "Acquisizione e media", "App e manutenzione", "Anteprima", "Incluso nell’app", "Configura"]
        case .ru: words = ["Избранное", "Расширенное", "Всё", "Захват и медиа", "Приложения и обслуживание", "Просмотр", "Включено в приложение", "Настроить"]
        case .tr: words = ["Odaklı", "Genişletilmiş", "Tümü", "Yakalama ve medya", "Uygulamalar ve bakım", "Önizleme", "Uygulamaya dahil", "Yapılandır"]
        case .ja: words = ["厳選", "拡張", "すべて", "キャプチャとメディア", "アプリとメンテナンス", "プレビュー", "アプリに含める", "設定"]
        case .ko: words = ["집중", "확장", "전체", "캡처 및 미디어", "앱 및 유지 관리", "미리 보기", "앱에 포함", "설정"]
        case .uk: words = ["Вибране", "Розширене", "Все", "Захоплення й медіа", "Програми й обслуговування", "Перегляд", "Включено в програму", "Налаштувати"]
        case .zhHans: words = ["精选", "扩展", "全部", "捕捉与媒体", "应用与维护", "预览", "包含在应用中", "配置"]
        case .zhTW, .zhHK: words = ["精選", "擴展", "全部", "擷取與媒體", "應用程式與維護", "預覽", "包含在應用程式中", "設定"]
        }
        return Self(simple: words[0], advanced: words[1], expert: words[2], capture: words[3],
                    applications: words[4], preview: words[5], included: words[6], configure: words[7],
                    controls: controlLabels(language))
    }
    private static func controlLabels(_ language: AppLanguage) -> [String] {
        switch language {
        case .enUS: return [
            "Show",
            "Feature visibility",
            "%d features hidden",
            "%d features shown",
            "%1$d hidden by %2$@",
            "Hidden features keep running. Sidebar search finds every feature.",
            "Search visible features",
            "Category",
            "All categories",
            "Included only",
            "Included first",
            "Restore the configuration from before the last bulk change.",
            "Not included",
            "Requires Dynamic Island to be on",
            "Included · behavior off",
            "Included · behavior on",
            "Included · available on demand",
            "Turn on",
            "Include or remove this feature throughout the app. Saved settings are kept.",
            "Close preview",
            "Illustrated example · fictional sample data",
            "Previewing never enables a feature or requests permissions.",
            "Pause",
            "Play"
        ]
        case .ptBR: return [
            "Mostrar",
            "Visibilidade de recursos",
            "%d recursos ocultos",
            "%d recursos exibidos",
            "%1$d ocultos por %2$@",
            "Recursos ocultos continuam funcionando. A busca lateral encontra todos os recursos.",
            "Buscar recursos visíveis",
            "Categoria",
            "Todas as categorias",
            "Somente incluídos",
            "Incluídos primeiro",
            "Restaurar a configuração anterior à última alteração em lote.",
            "Não incluído",
            "Requer Dynamic Island ativada",
            "Incluído · desativado",
            "Incluído · ativado",
            "Incluído · disponível sob demanda",
            "Ativar",
            "Inclua ou remova este recurso no app. As configurações salvas são mantidas.",
            "Fechar prévia",
            "Exemplo ilustrado · dados fictícios",
            "A prévia nunca ativa recursos nem solicita permissões.",
            "Pausar",
            "Reproduzir"
        ]
        case .es: return [
            "Mostrar",
            "Visibilidad de funciones",
            "%d funciones ocultas",
            "%d funciones visibles",
            "%1$d ocultas por %2$@",
            "Las funciones ocultas siguen funcionando. La búsqueda lateral encuentra todas.",
            "Buscar funciones visibles",
            "Categoría",
            "Todas las categorías",
            "Solo incluidas",
            "Incluidas primero",
            "Restaurar la configuración anterior al último cambio en bloque.",
            "No incluida",
            "Requiere Dynamic Island activada",
            "Incluida · desactivada",
            "Incluida · activada",
            "Incluida · disponible bajo demanda",
            "Activar",
            "Incluye o elimina esta función en la app. Se conservan los ajustes guardados.",
            "Cerrar vista previa",
            "Ejemplo ilustrado · datos ficticios",
            "La vista previa nunca activa funciones ni solicita permisos.",
            "Pausar",
            "Reproducir"
        ]
        case .sk: return [
            "Zobraziť",
            "Viditeľnosť funkcií",
            "%d skrytých funkcií",
            "%d zobrazených funkcií",
            "%1$d skrytých v režime %2$@",
            "Skryté funkcie zostávajú spustené. Vyhľadávanie v bočnom paneli nájde všetky.",
            "Hľadať viditeľné funkcie",
            "Kategória",
            "Všetky kategórie",
            "Len zahrnuté",
            "Zahrnuté najprv",
            "Obnoviť nastavenia pred poslednou hromadnou zmenou.",
            "Nezahrnuté",
            "Vyžaduje zapnutý Dynamic Island",
            "Zahrnuté · vypnuté",
            "Zahrnuté · zapnuté",
            "Zahrnuté · dostupné na požiadanie",
            "Zapnúť",
            "Zahrnúť alebo odstrániť túto funkciu v aplikácii. Uložené nastavenia sa zachovajú.",
            "Zavrieť ukážku",
            "Ilustrovaný príklad · fiktívne údaje",
            "Ukážka nezapína funkcie ani nežiada oprávnenia.",
            "Pozastaviť",
            "Prehrať"
        ]
        case .de: return [
            "Anzeigen",
            "Funktionsanzeige",
            "%d Funktionen ausgeblendet",
            "%d Funktionen angezeigt",
            "%1$d durch %2$@ ausgeblendet",
            "Ausgeblendete Funktionen laufen weiter. Die Suche in der Seitenleiste findet alle.",
            "Sichtbare Funktionen suchen",
            "Kategorie",
            "Alle Kategorien",
            "Nur enthaltene",
            "Enthaltene zuerst",
            "Konfiguration vor der letzten Sammeländerung wiederherstellen.",
            "Nicht enthalten",
            "Erfordert aktiviertes Dynamic Island",
            "Enthalten · deaktiviert",
            "Enthalten · aktiviert",
            "Enthalten · bei Bedarf verfügbar",
            "Aktivieren",
            "Diese Funktion in der App hinzufügen oder entfernen. Gespeicherte Einstellungen bleiben erhalten.",
            "Vorschau schließen",
            "Illustriertes Beispiel · fiktive Daten",
            "Die Vorschau aktiviert keine Funktionen und fordert keine Berechtigungen an.",
            "Pause",
            "Abspielen"
        ]
        case .fr: return [
            "Afficher",
            "Visibilité des fonctions",
            "%d fonctions masquées",
            "%d fonctions affichées",
            "%1$d masquées par %2$@",
            "Les fonctions masquées restent actives. La recherche latérale les trouve toutes.",
            "Rechercher les fonctions visibles",
            "Catégorie",
            "Toutes les catégories",
            "Incluses uniquement",
            "Incluses en premier",
            "Restaurer la configuration avant la dernière modification groupée.",
            "Non incluse",
            "Nécessite Dynamic Island activée",
            "Incluse · désactivée",
            "Incluse · activée",
            "Incluse · disponible à la demande",
            "Activer",
            "Inclure ou retirer cette fonction dans l’app. Les réglages enregistrés sont conservés.",
            "Fermer l’aperçu",
            "Exemple illustré · données fictives",
            "L’aperçu n’active jamais de fonction et ne demande aucune autorisation.",
            "Pause",
            "Lire"
        ]
        case .it: return [
            "Mostra",
            "Visibilità delle funzioni",
            "%d funzioni nascoste",
            "%d funzioni mostrate",
            "%1$d nascoste da %2$@",
            "Le funzioni nascoste restano attive. La ricerca laterale le trova tutte.",
            "Cerca funzioni visibili",
            "Categoria",
            "Tutte le categorie",
            "Solo incluse",
            "Incluse prima",
            "Ripristina la configurazione precedente all’ultima modifica di gruppo.",
            "Non inclusa",
            "Richiede Dynamic Island attiva",
            "Inclusa · disattivata",
            "Inclusa · attivata",
            "Inclusa · disponibile su richiesta",
            "Attiva",
            "Includi o rimuovi questa funzione nell’app. Le impostazioni salvate vengono conservate.",
            "Chiudi anteprima",
            "Esempio illustrato · dati fittizi",
            "L’anteprima non attiva funzioni né richiede permessi.",
            "Pausa",
            "Riproduci"
        ]
        case .ru: return [
            "Показать",
            "Видимость функций",
            "Скрыто функций: %d",
            "Показано функций: %d",
            "Скрыто: %1$d · %2$@",
            "Скрытые функции продолжают работать. Поиск в боковой панели находит все функции.",
            "Поиск видимых функций",
            "Категория",
            "Все категории",
            "Только включённые",
            "Сначала включённые",
            "Восстановить конфигурацию до последнего массового изменения.",
            "Не включено",
            "Требуется включить Dynamic Island",
            "Включено · действие выключено",
            "Включено · действие включено",
            "Включено · доступно по запросу",
            "Включить",
            "Добавить или убрать эту функцию во всём приложении. Сохранённые настройки останутся.",
            "Закрыть просмотр",
            "Иллюстрированный пример · вымышленные данные",
            "Просмотр не включает функции и не запрашивает разрешения.",
            "Пауза",
            "Воспроизвести"
        ]
        case .uk: return [
            "Показати",
            "Видимість функцій",
            "Приховано функцій: %d",
            "Показано функцій: %d",
            "Приховано: %1$d · %2$@",
            "Приховані функції продовжують працювати. Пошук у бічній панелі знаходить усі функції.",
            "Пошук видимих функцій",
            "Категорія",
            "Усі категорії",
            "Лише включені",
            "Спочатку включені",
            "Відновити конфігурацію до останньої масової зміни.",
            "Не включено",
            "Потрібно ввімкнути Dynamic Island",
            "Включено · дію вимкнено",
            "Включено · дію ввімкнено",
            "Включено · доступно на запит",
            "Увімкнути",
            "Додати або прибрати цю функцію в усьому застосунку. Збережені налаштування залишаться.",
            "Закрити перегляд",
            "Ілюстрований приклад · вигадані дані",
            "Перегляд не вмикає функції та не запитує дозволи.",
            "Пауза",
            "Відтворити"
        ]
        case .tr: return [
            "Göster",
            "Özellik görünürlüğü",
            "%d özellik gizli",
            "%d özellik gösteriliyor",
            "%2$@ ile %1$d gizli",
            "Gizli özellikler çalışmaya devam eder. Kenar çubuğu araması tüm özellikleri bulur.",
            "Görünür özellikleri ara",
            "Kategori",
            "Tüm kategoriler",
            "Yalnızca dahil olanlar",
            "Dahil olanlar önce",
            "Son toplu değişiklikten önceki yapılandırmayı geri yükle.",
            "Dahil değil",
            "Dynamic Island açık olmalı",
            "Dahil · kapalı",
            "Dahil · açık",
            "Dahil · istek üzerine kullanılabilir",
            "Aç",
            "Bu özelliği uygulamaya dahil et veya kaldır. Kaydedilen ayarlar korunur.",
            "Önizlemeyi kapat",
            "Resimli örnek · kurgusal veriler",
            "Önizleme özellikleri açmaz veya izin istemez.",
            "Duraklat",
            "Oynat"
        ]
        case .ja: return [
            "表示",
            "機能の表示範囲",
            "%d個の機能を非表示",
            "%d個の機能を表示",
            "%1$d個を%2$@で非表示",
            "非表示の機能も動作を続けます。サイドバー検索ですべての機能が見つかります。",
            "表示中の機能を検索",
            "カテゴリ",
            "すべてのカテゴリ",
            "含まれる機能のみ",
            "含まれる機能を先に",
            "直前の一括変更前の設定に戻します。",
            "含まれていません",
            "Dynamic Islandをオンにする必要があります",
            "含まれる機能 · 動作オフ",
            "含まれる機能 · 動作オン",
            "含まれる機能 · 必要時に使用可能",
            "オンにする",
            "アプリ全体でこの機能を追加または削除します。保存した設定は保持されます。",
            "プレビューを閉じる",
            "図解例 · 架空のサンプルデータ",
            "プレビューで機能が有効になることや権限が要求されることはありません。",
            "一時停止",
            "再生"
        ]
        case .ko: return [
            "표시",
            "기능 표시 범위",
            "기능 %d개 숨김",
            "기능 %d개 표시",
            "%2$@에서 %1$d개 숨김",
            "숨겨진 기능도 계속 실행됩니다. 사이드바 검색으로 모든 기능을 찾을 수 있습니다.",
            "표시된 기능 검색",
            "카테고리",
            "모든 카테고리",
            "포함된 기능만",
            "포함된 기능 먼저",
            "마지막 일괄 변경 전 설정을 복원합니다.",
            "포함되지 않음",
            "Dynamic Island를 켜야 합니다",
            "포함됨 · 동작 꺼짐",
            "포함됨 · 동작 켜짐",
            "포함됨 · 필요할 때 사용 가능",
            "켜기",
            "앱 전체에서 이 기능을 포함하거나 제거합니다. 저장된 설정은 유지됩니다.",
            "미리 보기 닫기",
            "그림 예시 · 가상 데이터",
            "미리 보기는 기능을 켜거나 권한을 요청하지 않습니다.",
            "일시 정지",
            "재생"
        ]
        case .zhHans: return [
            "显示",
            "功能显示范围",
            "已隐藏 %d 项功能",
            "已显示 %d 项功能",
            "%2$@隐藏 %1$d 项",
            "隐藏的功能仍在运行。侧栏搜索可找到所有功能。",
            "搜索显示的功能",
            "类别",
            "所有类别",
            "仅已包含",
            "已包含优先",
            "恢复上次批量更改前的配置。",
            "未包含",
            "需要开启 Dynamic Island",
            "已包含 · 行为关闭",
            "已包含 · 行为开启",
            "已包含 · 按需使用",
            "开启",
            "在整个应用中包含或移除此功能。已保存的设置会保留。",
            "关闭预览",
            "图示示例 · 虚构数据",
            "预览不会开启功能或请求权限。",
            "暂停",
            "播放"
        ]
        case .zhTW, .zhHK: return [
            "顯示",
            "功能顯示範圍",
            "已隱藏 %d 項功能",
            "已顯示 %d 項功能",
            "%2$@隱藏 %1$d 項",
            "隱藏的功能仍在執行。側欄搜尋可找到所有功能。",
            "搜尋顯示的功能",
            "類別",
            "所有類別",
            "僅已包含",
            "已包含優先",
            "還原上次批次變更前的設定。",
            "未包含",
            "需要開啟 Dynamic Island",
            "已包含 · 行為關閉",
            "已包含 · 行為開啟",
            "已包含 · 按需使用",
            "開啟",
            "在整個應用程式中包含或移除此功能。已儲存的設定會保留。",
            "關閉預覽",
            "圖示範例 · 虛構資料",
            "預覽不會開啟功能或要求權限。",
            "暫停",
            "播放"
        ]
        }
    }

}
