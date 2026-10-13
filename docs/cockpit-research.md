# Возможности Cockpit и направления для ServerDeck

Дата обзора: 10 октября 2026 года.

Cockpit — бесплатный графический интерфейс администрирования Linux. Он работает с существующими системными инструментами и позволяет пользоваться GUI вместе с SSH, командной строкой и Ansible. Для ServerDeck это прямой ориентир по диагностике и управлению отдельным сервером. [О проекте](https://cockpit-project.org/).

Главный вывод для продукта: метрики, журналы и кнопки управления службами уже доступны в готовом решении. Возможное отличие ServerDeck стоит искать в общем рабочем пространстве серверов, поддержке Windows как клиентской платформы и управлении жизненным циклом конкретного ПО с планом изменений. Это продуктовые гипотезы, а не подтверждённые преимущества на рынке.

## Границы обзора

Ниже описаны системные функции и все 48 позиций официального каталога расширений на дату обзора. Каталог открыт для дополнений, поэтому он не охватывает любой существующий сторонний плагин. Наличие записи в каталоге не означает, что модуль установлен по умолчанию, доступен в каждом дистрибутиве или поддерживается командой Cockpit. [Каталог](https://cockpit-project.org/applications.html).

Обзор основан на документации, без установки Cockpit и практической проверки интерфейса. Системные зависимости сверены с исходниками руководства в ревизии [2f57692](https://github.com/cockpit-project/cockpit/tree/2f57692b9c4dbc6ca685bef11fc7bff6bc02cec2/doc/modules/guide/pages). Эта ревизия ветки разработки не означает одинаковую доступность функций во всех выпущенных пакетах.

## Подключение и архитектура

### Веб консоль на сервере

Обычный вариант — установить Cockpit на Linux и открыть его по HTTPS, по умолчанию на порту 9090. Доступны пакеты для Fedora, RHEL, CentOS, Debian, Ubuntu, Arch и семейства SUSE. Поддерживаемая версия и состав пакетов зависят от дистрибутива; для Debian и Ubuntu проект рекомендует рассмотреть backports. Клиентом выступает браузер, в том числе на Windows и macOS. [Установка](https://cockpit-project.org/running.html).

Веб-служба может запускаться по запросу через systemd socket activation. Это не означает, что сбор исторических метрик и все подключённые системные службы прекращают работать после закрытия интерфейса. [О проекте](https://cockpit-project.org/), [метрики PCP](https://github.com/cockpit-project/cockpit/blob/2f57692b9c4dbc6ca685bef11fc7bff6bc02cec2/doc/modules/guide/pages/feature-pcp.adoc).

### Доступ через SSH

Веб-порт необязательно открывать на каждой управляемой машине. Можно использовать отдельный хост с контейнером `cockpit/ws`, который подключается к целевому серверу через SSH. Существует и Cockpit Client для Linux, распространяемый через Flatpak. [Варианты доступа](https://cockpit-project.org/faq.html).

Cockpit Client использует локальную SSH-конфигурацию: псевдонимы, известные ключи хостов, файлы ключей и аппаратные токены. Страница приложения указывает Python как требование на сервере; включать там веб-сервер Cockpit и открывать дополнительные порты не требуется. Зависимости конкретных функций и модулей всё равно нужно проверять отдельно. [Cockpit Client](https://flathub.org/en/apps/org.cockpit_project.CockpitClient).

Следствие для ServerDeck: формулировки «через SSH», «без облака» и «без открытого веб-порта» сами по себе не доказывают уникальность.

### Несколько серверов

Исторически Cockpit позволял добавлять хосты и переключаться между ними в одной сессии, используя SSH. Однако этот механизм помечен устаревшим с версии 322. Причина: интерфейс загружает код разных хостов в общий браузерный контекст; такие хосты должны быть доверенными. В некоторых конфигурациях механизм отключён. [Управление несколькими хостами](https://github.com/cockpit-project/cockpit/blob/2f57692b9c4dbc6ca685bef11fc7bff6bc02cec2/doc/modules/guide/pages/multi-host.adoc).

Поэтому переключатель хостов нельзя автоматически считать современной платформой управления парком серверов. Подключение к отдельному серверу через SSH остаётся отдельным сценарием. Для ServerDeck имеет смысл исследовать потребность в сводном инвентаре, поиске ПО по всем серверам и независимой обработке каждого подключения.

## Системные возможности

### Информация о системе и питание

Cockpit читает сведения о хосте, ОС, ядре и архитектуре; позволяет менять имя машины, время и часовой пояс. Управление списком NTP-серверов зависит от использования `systemd-timesyncd`. Доступны перезагрузка и выключение, включая отложенное выключение. Используются стандартные механизмы systemd и системные команды. [Системные операции](https://github.com/cockpit-project/cockpit/blob/2f57692b9c4dbc6ca685bef11fc7bff6bc02cec2/doc/modules/guide/pages/feature-systemd.adoc).

Если установлен TuneD, можно выбирать профили производительности. Это отдельная зависимость, а не универсальная настройка любой ОС. [TuneD](https://github.com/cockpit-project/cockpit/blob/2f57692b9c4dbc6ca685bef11fc7bff6bc02cec2/doc/modules/guide/pages/feature-tuned.adoc).

### Метрики и история

Доступен обзор производительности, включая CPU, память, дисковую и сетевую активность. Для исторических графиков Cockpit использует Performance Co-Pilot, если он установлен. Архивирование зависит от работающего `pmlogger`; без PCP текущие метрики собираются самим Cockpit, но архивные возможности отсутствуют. PCP также допускает внешнюю визуализацию через Grafana. [Метрики и зависимости](https://github.com/cockpit-project/cockpit/blob/2f57692b9c4dbc6ca685bef11fc7bff6bc02cec2/doc/modules/guide/pages/feature-pcp.adoc).

Для сравнения с ServerDeck нужно различать краткую локальную историю измерений и серверное долговременное архивирование.

### Службы и systemd

Интерфейс позволяет просматривать состояние systemd units и управлять ими. В документации RHEL описаны службы, targets, sockets, timers и paths, а также запуск, остановка и включение или отключение автозапуска. Возможности применимы с учётом прав пользователя. [Управление службами в RHEL](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/pdf/system_administrators_guide/red_hat_enterprise_linux-8-system_administrators_guide-en-us.pdf).

Cockpit использует API systemd; альтернативные системные API в соответствующем разделе руководства не реализованы. Поэтому наличие Linux и SSH ещё не гарантирует управление службами в минимальном контейнере или системе с другим init. [Зависимость от systemd](https://github.com/cockpit-project/cockpit/blob/2f57692b9c4dbc6ca685bef11fc7bff6bc02cec2/doc/modules/guide/pages/feature-systemd.adoc).

### Системные журналы

Источник — systemd journal, доступ через `journalctl`. Записи используются как на общей странице журналов, так и рядом с системными операциями. [Источник журналов](https://github.com/cockpit-project/cockpit/blob/2f57692b9c4dbc6ca685bef11fc7bff6bc02cec2/doc/modules/guide/pages/feature-journal.adoc).

Документация RHEL 10 описывает просмотр деталей записи, фильтрацию по времени, приоритету и идентификатору, паузу поступления новых записей и возобновление просмотра. Это не универсальный агрегатор произвольных файлов логов всех приложений. [Просмотр и фильтрация](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/pdf/risk_reduction_and_recovery_operations/related-information).

### Сеть и firewall

Сетевой интерфейс работает через NetworkManager и его D-Bus API. Доступность управления зависит от того, обслуживает ли NetworkManager конкретные интерфейсы; устройства, помеченные как неуправляемые, могут не отображаться. [Сетевой backend](https://github.com/cockpit-project/cockpit/blob/2f57692b9c4dbc6ca685bef11fc7bff6bc02cec2/doc/modules/guide/pages/feature-networkmanager.adoc).

Для firewall используется firewalld; без него соответствующий UI отсутствует. Руководство описывает показ, добавление и удаление предопределённых сервисов в зоне по умолчанию. Не следует считать это обещанием полноценного редактора любых правил nftables, iptables или UFW. Детальный набор действий нужно сверять с целевой версией. [Firewall](https://github.com/cockpit-project/cockpit/blob/2f57692b9c4dbc6ca685bef11fc7bff6bc02cec2/doc/modules/guide/pages/feature-firewall.adoc).

### Диски и хранилища

`cockpit-storaged` предоставляет управление хранилищем: разделами, монтированием, шифрованием, NFS, RAID и iSCSI. [Модуль Storage](https://cockpit-project.org/applications.html).

Системный backend определяет доступность операций с LVM, multipath и Btrfs. Руководство также оговаривает различия между storaged и udisks и ограничения некоторых операций при использовании udisks. Изменения, сделанные стандартными LVM-инструментами, обнаруживаются Cockpit. Это управление системным хранилищем, а не только график заполнения диска. [Зависимости хранилища](https://github.com/cockpit-project/cockpit/blob/2f57692b9c4dbc6ca685bef11fc7bff6bc02cec2/doc/modules/guide/pages/feature-storaged.adoc).

### Обновления и установка пакетов

Основной модуль обновлений обращается к PackageKit через D-Bus: показывает доступные обновления и применяет их. Для OSTree есть отдельный модуль. [PackageKit](https://github.com/cockpit-project/cockpit/blob/2f57692b9c4dbc6ca685bef11fc7bff6bc02cec2/doc/modules/guide/pages/feature-packagekit.adoc), [OSTree](https://github.com/cockpit-project/cockpit-ostree).

Обновление ОС следует отличать от выбора и установки произвольного пакета. Для установки и удаления в каталоге есть дополнительные модули SUSE Packages, сторонний Package Manager и Pacman Package Manager. Нельзя сравнивать ServerDeck только с базовой страницей Software Updates и игнорировать расширения. [Каталог](https://cockpit-project.org/applications.html).

Установка пакета также не равна развёртыванию готовой базы данных: настройка репозитория, выбор точной версии, подготовка конфигурации и проверка результата могут требовать отдельного сценария.

### Учётные записи и домены

Cockpit управляет локальными пользователями стандартными системными инструментами. [Пользователи](https://github.com/cockpit-project/cockpit/blob/2f57692b9c4dbc6ca685bef11fc7bff6bc02cec2/doc/modules/guide/pages/feature-users.adoc).

В руководстве RHEL описаны создание, изменение и удаление аккаунтов, блокировка, срок действия пароля и завершение пользовательских сессий. [Операции с аккаунтами](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/html/managing_systems_using_the_rhel_7_web_console/managing-user-accounts-in-the-web-console_system-management-using-the-rhel-7-web-console).

При наличии realmd можно настраивать членство машины в Active Directory или IPA. Поддержка конкретного домена зависит от клиентского ПО на сервере. Это отличается от интерфейса управления LDAP-каталогом 389 Directory Server, который поставляется отдельным расширением. [realmd](https://github.com/cockpit-project/cockpit/blob/2f57692b9c4dbc6ca685bef11fc7bff6bc02cec2/doc/modules/guide/pages/feature-realmd.adoc).

### Доступ и полномочия

В обычной веб-конфигурации применяется системная аутентификация через PAM; предусмотрены Kerberos SSO и сертификаты или смарт-карты при соответствующей настройке. Для SSH-подключений используются доступные методы SSH и проверка ключа хоста. [Аутентификация](https://github.com/cockpit-project/cockpit/blob/2f57692b9c4dbc6ca685bef11fc7bff6bc02cec2/doc/modules/guide/pages/authentication.adoc).

Права сессии определяются ОС. Cockpit может повышать их через sudo или polkit; индикатор Administrative access позволяет переключать уровень доступа. Детальные разрешения на системные операции задаются правилами polkit. Это не отдельная универсальная ролевая модель для всей инфраструктуры. [Полномочия](https://github.com/cockpit-project/cockpit/blob/2f57692b9c4dbc6ca685bef11fc7bff6bc02cec2/doc/modules/guide/pages/privileges.adoc).

### Терминал и файлы

Встроенный терминал предоставляет обычную shell с правами, соответствующими пользовательской сессии. Он позволяет выполнять действия, для которых нет отдельного графического экрана, но такие действия не следует считать готовыми мастерами Cockpit. [Терминал](https://github.com/cockpit-project/cockpit/blob/2f57692b9c4dbc6ca685bef11fc7bff6bc02cec2/doc/modules/guide/pages/feature-terminal.adoc).

Для файлов существует отдельный официальный модуль Cockpit Files. В экосистеме также есть Navigator и Explorer с собственными интерфейсами и набором операций. [Cockpit Files](https://github.com/cockpit-project/cockpit-files).

### Виртуальные машины и контейнеры

`cockpit-machines` — отдельный интерфейс виртуальных машин. Он использует libvirt-dbus для получения состояния и операций, а virt-install и virt-xml — для создания и изменения определений машин. [Виртуальные машины](https://github.com/cockpit-project/cockpit-machines).

`cockpit-podman` управляет контейнерами Podman через его REST API. Его нельзя автоматически считать интерфейсом для Docker. Docker Manager, Docker Compose и systemd-nspawn присутствуют в каталоге как отдельные сторонние проекты. [Podman](https://github.com/cockpit-project/cockpit-podman).

### Диагностика и SELinux

Модуль SELinux позволяет менять режим enforcing или permissive, просматривать проблемы аудита через setroubleshootd и применять предложенные исправления. [SELinux](https://github.com/cockpit-project/cockpit/blob/2f57692b9c4dbc6ca685bef11fc7bff6bc02cec2/doc/modules/guide/pages/feature-selinux.adoc).

Diagnostic Reports собирает системную конфигурацию и диагностические сведения через sosreport. Kernel Dump предоставляет интерфейс к kdump для диагностики сбоев ядра. [sosreport](https://github.com/cockpit-project/cockpit/blob/2f57692b9c4dbc6ca685bef11fc7bff6bc02cec2/doc/modules/guide/pages/feature-sosreport.adoc), [kdump](https://cockpit-project.org/applications.html).

## Полный перечень модулей официального каталога

Раздел фиксирует состав каталога. Подробности основных модулей изложены выше; сторонние возможности ниже указаны по заявленному назначению. Статус «предварительный» соответствует пометке pre-release в каталоге. [Источник перечня](https://cockpit-project.org/applications.html).

### Модули команды Cockpit

| Модуль | Пакет или проект |
| --- | --- |
| Storage | `cockpit-storaged` |
| Network | `cockpit-networkmanager` |
| Software Updates PackageKit | `cockpit-packagekit` |
| Software Updates OSTree | `cockpit-ostree` |
| Virtual Machines | `cockpit-machines` |
| Podman Containers | `cockpit-podman` |
| SELinux | `cockpit-selinux` |
| Kernel Dump | `cockpit-kdump` |
| Diagnostic Reports | `cockpit-sosreport` |
| Cockpit Files | `cockpit-files` |

### Модули Red Hat и SUSE

| Разработчик | Модуль | Назначение |
| --- | --- | --- |
| Red Hat | [Cockpit Image Builder](https://github.com/osbuild/image-builder-frontend) | Образы ОС |
| Red Hat | 389 Directory Server | LDAP |
| Red Hat | [Session Recording](https://github.com/Scribery/cockpit-session-recording) | Запись сессий |
| Red Hat | [Subscription Manager](https://github.com/cockpit-project/subscription-manager-cockpit) | Подписки RHEL |
| Red Hat | [High Availability Cluster Management](https://github.com/ClusterLabs/pcs-web-ui) | Pacemaker |
| SUSE | [Software Updates transactional-update](https://github.com/openSUSE/cockpit-tukit) | Транзакционные обновления |
| SUSE | [Manage Repositories](https://github.com/openSUSE/cockpit-repos) | Репозитории |
| SUSE | [Subscription Manager](https://github.com/openSUSE/cockpit-subscriptions) | Подписки SLE |
| SUSE | [Packages](https://github.com/openSUSE/cockpit-packages) | Установка пакетов |
| SUSE | [Bootloader](https://github.com/openSUSE/cockpit-bootloader) | Загрузчик; предварительный |

### Сторонние модули

| Модуль | Назначение |
| --- | --- |
| ZFS Manager | ZFS |
| File Sharing | Samba, NFS |
| Navigator | Файлы |
| Benchmark | Тестирование хранилища |
| Sensors | Датчики |
| Tailscale | VPN; предварительный |
| Tailscaled | Tailscale |
| Headscale | Координатор; предварительный |
| Cloudflare tunnels | Туннели; предварительный |
| Docker Manager | Контейнеры; предварительный |
| Backblaze B2 backup | Бэкапы |
| ROS 2 Diagnostics | Диагностика ROS |
| Package Manager | DEB, RPM |
| Port Forward Manager | Проброс портов |
| Sudo Manager | Политики sudo |
| DNS Bind | DNS |
| Pacman Package Manager | Arch |
| Download Superstation | Торренты |
| Systemd-nspawn Containers | Системные контейнеры |
| Docker Compose | Стеки; предварительный |
| SCAP Compliance | Соответствие политикам |
| [Explorer](https://github.com/ismetozalp/explorer) | Файлы, редактор, терминалы |
| InFlight TV | IPTV |
| Cockpit Top | Мониторинг процессов |
| Manifest | Загрузки |
| cockpit-microshift | MicroShift |
| [Pilot](https://github.com/ismetozalp/pilot) | RustDesk |
| [Hangar](https://github.com/ismetozalp/hangar) | Резервное копирование |

Для продуктового сравнения особенно важно отдельно изучить Pilot: расширение предлагает мастер установки RustDesk с планом и журналом выполнения, а затем управление сервисом. Это заявленный сценарий специализированного приложения, близкий направлению ServerDeck; его удобство и надёжность нужно сравнивать практически. [Pilot](https://github.com/ismetozalp/pilot).

Некоторые расширения существенно шире краткого названия в таблице. Session Recording использует tlog, SSSD и journal для настройки и воспроизведения записей терминальных сессий. Explorer предлагает поиск файлов и содержимого, предпросмотр, редактор и терминалы. Hangar заявляет резервные копии по расписанию, дедупликацию, шифрование, управление сроками хранения и восстановление. Это возможности отдельных проектов с собственными зависимостями. [Session Recording](https://github.com/Scribery/cockpit-session-recording), [Explorer](https://github.com/ismetozalp/explorer), [Hangar](https://github.com/ismetozalp/hangar).

## Расширение и интеграция

Cockpit допускает собственные модули: интерфейсные файлы и `manifest.json` определяют страницы, пункты меню, зависимости и условия доступности. Есть JavaScript API для взаимодействия с системой. При этом руководство прямо указывает, что API для внешних HTTP или REST-вызовов не предоставляется; недокументированные интерфейсы считаются внутренними. [Модули и API](https://github.com/cockpit-project/cockpit/blob/2f57692b9c4dbc6ca685bef11fc7bff6bc02cec2/doc/modules/guide/pages/packages.adoc).

Можно встраивать весь Cockpit или документированные компоненты в веб-приложение. Для обычного iframe-встраивания требуется одинаковый origin, обычно обеспечиваемый общим reverse proxy. Глубокая интеграция отмечена как изменяющаяся и недокументированная. Поэтому использовать Cockpit как готовый backend для Flutter без отдельного технического исследования нельзя. [Встраивание](https://github.com/cockpit-project/cockpit/blob/2f57692b9c4dbc6ca685bef11fc7bff6bc02cec2/doc/modules/guide/pages/embedding.adoc).

## Ограничения для неоднородной среды

| Условие | Что это означает |
| --- | --- |
| Управляемая ОС — Linux | Браузер на Windows не означает управление Windows Server |
| Системные функции опираются на systemd | Минимальные контейнеры и другие init требуют отдельной оценки |
| Сеть опирается на NetworkManager | netplan или systemd-networkd нельзя считать автоматически поддержанными тем же UI |
| Firewall опирается на firewalld | UFW и произвольные правила не равны этому модулю |
| Обновления опираются на PackageKit | Поведение определяется backend и дистрибутивом |
| Архив метрик требует PCP | Текущие графики и долговременная история имеют разные требования |
| Расширения устанавливаются отдельно | Название Cockpit не гарантирует одинаковые возможности на всех хостах |
| Переключатель хостов устарел | Нужно проверять версию и конфигурацию перед сравнением работы с несколькими серверами |

Источники условий приведены в соответствующих системных разделах. Пример реального ограничения интеграции: FAQ описывает ошибку обновления в некоторых Ubuntu-конфигурациях, когда PackageKit получает от NetworkManager состояние offline, хотя сеть обслуживается другим стеком. Это иллюстрирует зависимость от окружения, а не утверждение, что Cockpit не работает на Ubuntu. [FAQ](https://cockpit-project.org/faq.html).

## Что можно использовать для ServerDeck

Следующие варианты — предложения для обсуждения; они не меняют спецификации и не означают решение о реализации.

### Использовать как ориентир для интерфейса

Первым стоит сравнить путь «проблемная служба → состояние → журнал → действие», разделение обычного и административного доступа, отображение недоступных функций и связь графиков с диагностикой. Пользователь должен понимать, что произошло и какие операции доступны именно на этом сервере.

### Проверить отличия продукта

| Направление | Основание для гипотезы | Что нужно проверить |
| --- | --- | --- |
| Клиент для Windows | Cockpit Client в рассмотренном источнике распространяется для Linux | Насколько нужен отдельный клиент при наличии веб-консоли |
| Общий инвентарь нескольких серверов | Старый механизм общей сессии Cockpit устарел | Нужны ли сводные версии ПО, поиск и сравнение хостов |
| Жизненный цикл конкретного ПО | Обновления пакетов и обслуживание приложения решают разные задачи | Установка, принятие существующей конфигурации, обновление, бэкап, восстановление |
| План изменений и результат задания | ServerDeck уже описывает планы и локальную историю заданий | Удобство подтверждения, диагностика обрыва связи и восстановление состояния |
| Возможности по окружению | Cockpit зависит от системных backend | Какие ОС и варианты установки реально нужны пользователям |

Описание ServerDeck для этих гипотез взято из [README проекта](../README.md). Это сравнение заявленного подхода, без аудита реализации или подтверждения всех функций приложения.

### Рассмотреть совместное использование

Возможны три направления:

1. Развивать самостоятельный SSH-клиент, используя Cockpit как ориентир для системных сценариев. Потребуется собственная поддержка команд, парсеров и различий ОС.
2. Добавить переход из ServerDeck в уже установленный Cockpit для глубокого администрирования. Это кандидат на небольшой прототип, но нужно продумать адрес, аутентификацию и контекст выбранного хоста.
3. Создать собственный модуль Cockpit для специализированного управления ПО. Такой вариант использует существующую консоль, но меняет платформу и способ поставки продукта.

Встраивание интерфейса и использование внутреннего протокола Cockpit — отдельные исследования с большей неопределённостью. Их стоит оценивать после более простого перехода в веб-консоль.

## Практическое сравнение перед выбором функций

На одноразовых VM Ubuntu 24.04 и одного дистрибутива семейства RHEL можно пройти одинаковые сценарии в Cockpit и ServerDeck:

1. Подключить сервер и выяснить, какие компоненты потребовалось установить.
2. Найти неработающую службу и открыть относящиеся к ней журналы.
3. Посмотреть метрики и проверить, какая история остаётся после закрытия клиента.
4. Посмотреть доступные обновления и отдельно проверить установку нового пакета.
5. Попробовать сценарий конкретного приложения: версия, конфигурация, данные и итоговая проверка.
6. Подключить второй сервер и оценить сводный обзор и ограничения общей сессии.
7. Проверить обычного пользователя и повышение прав.

Для каждого сценария зафиксировать время до результата, число действий, зависимости, качество объяснения ошибки и восстановление после разрыва связи. До этого сравнения разумно считать Cockpit сильным функциональным ориентиром, а предполагаемые преимущества ServerDeck — проверяемыми гипотезами.
