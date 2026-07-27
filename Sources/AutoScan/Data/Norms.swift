import Foundation

/// Состояние двигателя в момент замера — от него зависит, какая норма применима.
/// Одно и то же давление во впуске нормально на заглушенном моторе
/// и означает неисправность на работающем.
struct EngineContext {
    var running: Bool = false
    var coolantTemp: Double?
    var rpm: Double?
    var ambientTemp: Double?
    var speed: Double?

    /// Двигатель прогрет до рабочей температуры.
    var warmedUp: Bool { (coolantTemp ?? 0) >= 75 }
    /// Холостой ход: работает, но машина стоит.
    var atIdle: Bool { running && (speed ?? 0) < 3 && (rpm ?? 0) < 1400 }

    static func from(_ r: ScanReport) -> EngineContext {
        EngineContext(running: r.engineRunning,
                      coolantTemp: r.value(pid: 0x05),
                      rpm: r.value(pid: 0x0C),
                      ambientTemp: r.value(pid: 0x46),
                      speed: r.value(pid: 0x0D))
    }
}

enum NormStatus {
    case normal          // в пределах нормы
    case low             // ниже нормы
    case high            // выше нормы
    case notApplicable   // норму в этих условиях проверить нельзя

    var title: String {
        switch self {
        case .normal:         return Loc.t("норма", "normal")
        case .low:            return Loc.t("ниже нормы", "below normal")
        case .high:           return Loc.t("выше нормы", "above normal")
        case .notApplicable:  return Loc.t("не оценивается", "not assessed")
        }
    }

    var isDeviation: Bool { self == .low || self == .high }

    var symbol: String {
        switch self {
        case .normal:        return "checkmark.circle.fill"
        case .low:           return "arrow.down.circle.fill"
        case .high:          return "arrow.up.circle.fill"
        case .notApplicable: return "minus.circle"
        }
    }
}

/// Оценка одного значения относительно нормы, с объяснением.
struct NormAssessment {
    var status: NormStatus
    /// Норма в человеческом виде: «80–105 °C при прогретом двигателе».
    var rangeText: String
    /// Что означает именно это отклонение.
    var meaning: String?
    /// Куда смотреть.
    var whatToCheck: String?
}

// MARK: - Справочник параметров

enum ParameterGuide {

    /// Что этот параметр вообще означает — простыми словами, без терминов.
    static func about(pid: UInt8) -> String? {
        switch pid {
        case 0x03: return Loc.t(
            "Показывает, работает ли двигатель по показаниям кислородного датчика (замкнутый контур) или по заводским таблицам (открытый контур). На прогретом моторе должен быть замкнутый контур — иначе расход растёт, а состав смеси никто не контролирует.",
            "Shows whether the engine is trimming fuel by the oxygen sensor (closed loop) or running off factory tables (open loop). A warm engine should be in closed loop; otherwise fuel use rises and nothing controls the mixture.")
        case 0x04: return Loc.t(
            "Насколько сильно двигатель загружен прямо сейчас, в процентах от максимума. На холостом ходу — небольшая величина, при разгоне приближается к 100%.",
            "How hard the engine is working right now, as a percentage of maximum. Low at idle, close to 100% under full acceleration.")
        case 0x05: return Loc.t(
            "Температура охлаждающей жидкости — главный показатель теплового состояния двигателя. По ней блок решает, сколько лить топлива.",
            "Coolant temperature — the main indicator of the engine's thermal state. The ECU uses it to decide how much fuel to inject.")
        case 0x06, 0x08: return Loc.t(
            "Быстрая поправка количества топлива, которую блок вносит прямо сейчас по показаниям кислородного датчика. Постоянно колеблется около нуля — это нормально.",
            "The fast fuel correction the ECU is applying right now based on the oxygen sensor. Constantly fluctuating around zero is normal.")
        case 0x07, 0x09: return Loc.t(
            "Накопленная поправка топлива — то, насколько двигатель систематически отклоняется от заводской настройки. Самый информативный параметр для поиска подсоса воздуха и проблем с подачей топлива.",
            "The learned long-term fuel correction — how far the engine systematically deviates from factory calibration. The single most useful parameter for finding air leaks and fuel delivery problems.")
        case 0x0A: return Loc.t(
            "Давление топлива в магистрали низкого давления. Падение означает слабый насос или забитый фильтр.",
            "Fuel pressure in the low-pressure line. A drop means a weak pump or a clogged filter.")
        case 0x0B: return Loc.t(
            "Давление во впускном коллекторе. На заглушенном моторе равно атмосферному (около 100 кПа), на холостом ходу двигатель создаёт разрежение и значение падает. Высокое значение на холостых — признак подсоса или проблем с дросселем.",
            "Intake manifold pressure. With the engine off it equals atmospheric (about 100 kPa); at idle the engine creates vacuum and the value drops. A high value at idle indicates an air leak or throttle problem.")
        case 0x0C: return Loc.t(
            "Обороты коленчатого вала. На прогретом холостом ходу должны быть стабильными — плавание оборотов само по себе симптом.",
            "Crankshaft speed. At warm idle it should be steady — a fluctuating idle is itself a symptom.")
        case 0x0E: return Loc.t(
            "Насколько раньше верхней мёртвой точки поджигается смесь. Блок отводит угол назад, когда слышит детонацию или не доверяет датчикам — отсюда вялый разгон.",
            "How far before top dead centre the mixture is ignited. The ECU retards timing when it hears knock or distrusts the sensors — which is why the car feels sluggish.")
        case 0x0F: return Loc.t(
            "Температура воздуха на впуске. На холодном моторе близка к забортной; сильно завышенная говорит о подсосе горячего воздуха из моторного отсека.",
            "Intake air temperature. On a cold engine it is close to ambient; a much higher reading means hot engine-bay air is being drawn in.")
        case 0x10: return Loc.t(
            "Сколько воздуха проходит через расходомер. По этой цифре блок рассчитывает подачу топлива, поэтому её занижение — частая причина «нет тяги».",
            "How much air passes through the mass air flow sensor. The ECU calculates fuel from this figure, so an under-reading sensor is a common cause of power loss.")
        case 0x11, 0x45, 0x47, 0x48: return Loc.t(
            "Насколько открыта дроссельная заслонка. На холостом ходу — почти закрыта.",
            "How far the throttle plate is open. Nearly closed at idle.")
        case 0x1F: return Loc.t(
            "Сколько времени двигатель работает с момента последнего запуска. Многие показатели становятся достоверными только через несколько минут работы.",
            "How long the engine has been running since the last start. Many readings only become meaningful after several minutes.")
        case 0x21: return Loc.t(
            "Сколько километров машина проехала с горящей лампой Check. Большое значение означает, что неисправность игнорировали долго.",
            "How many kilometres the car was driven with the Check Engine light on. A large figure means the fault was ignored for a long time.")
        case 0x2C, 0x2D: return Loc.t(
            "Управление клапаном рециркуляции отработавших газов. На холостом ходу клапан обычно закрыт.",
            "Exhaust gas recirculation valve control. The valve is normally closed at idle.")
        case 0x2F: return Loc.t(
            "Уровень топлива в баке. Полезен при проверке: пустой бак мешает оценить работу бензонасоса под нагрузкой.",
            "Fuel level in the tank. Relevant during a check: a nearly empty tank makes it hard to assess the pump under load.")
        case 0x30: return Loc.t(
            "Сколько раз двигатель полностью прогревался с момента последнего сброса ошибок. Малое число при большом пробеге означает недавний сброс памяти.",
            "How many full warm-up cycles have occurred since codes were last cleared. A small number on a high-mileage car means the memory was cleared recently.")
        case 0x31: return Loc.t(
            "Пробег с момента последнего стирания ошибок. Один из самых надёжных способов понять, что память чистили перед продажей.",
            "Distance driven since fault codes were last cleared. One of the most reliable ways to tell that memory was wiped before a sale.")
        case 0x33: return Loc.t(
            "Атмосферное давление по датчику. Заодно проверка исправности самого датчика: на уровне моря около 100 кПа.",
            "Barometric pressure from the sensor. Also a sanity check on the sensor itself: about 100 kPa at sea level.")
        case 0x3C, 0x3D, 0x3E, 0x3F: return Loc.t(
            "Температура катализатора. Слишком низкая на прогретом моторе означает, что катализатор не работает; слишком высокая — что в него попадает несгоревшее топливо.",
            "Catalytic converter temperature. Too low on a warm engine means the catalyst is not working; too high means unburnt fuel is reaching it.")
        case 0x42: return Loc.t(
            "Напряжение питания блока управления — фактически напряжение бортовой сети. На заглушенной машине показывает состояние аккумулятора, на заведённой — работу генератора.",
            "Control module supply voltage — effectively the vehicle's system voltage. With the engine off it reflects battery condition; running, it reflects the alternator.")
        case 0x43: return Loc.t(
            "Нагрузка на двигатель с учётом температуры и оборотов. Более честная величина, чем обычная расчётная нагрузка.",
            "Engine load corrected for temperature and speed. A more honest figure than plain calculated load.")
        case 0x44: return Loc.t(
            "Заданный состав смеси. Единица означает идеальное соотношение воздуха и топлива, меньше единицы — обогащение.",
            "Commanded air-fuel equivalence. A value of 1 means the ideal ratio; below 1 means enrichment.")
        case 0x46: return Loc.t(
            "Температура за бортом по датчику машины.",
            "Outside air temperature from the vehicle's sensor.")
        case 0x4D: return Loc.t(
            "Сколько времени двигатель проработал с горящей лампой Check.",
            "How long the engine has run with the Check Engine light on.")
        case 0x4E: return Loc.t(
            "Сколько времени прошло с момента последнего стирания ошибок.",
            "How much time has passed since fault codes were last cleared.")
        case 0x51: return Loc.t(
            "Тип топлива, на который настроен двигатель.",
            "The fuel type the engine is configured for.")
        case 0x52: return Loc.t(
            "Доля этанола в топливе. Имеет смысл на машинах, рассчитанных на спиртовые смеси.",
            "Ethanol content of the fuel. Meaningful on flex-fuel vehicles.")
        case 0x5C: return Loc.t(
            "Температура моторного масла. Прогревается заметно медленнее охлаждающей жидкости — по ней видно, действительно ли двигатель вышел на режим.",
            "Engine oil temperature. It warms up noticeably slower than coolant, so it shows whether the engine has truly reached operating temperature.")
        case 0x5E: return Loc.t(
            "Мгновенный расход топлива двигателем.",
            "Instantaneous engine fuel consumption.")
        case 0xA6: return Loc.t(
            "Пробег, который сообщает сам блок управления. Есть не на всех машинах, но если есть — его можно сверить с показаниями приборной панели.",
            "Odometer reading reported by the ECU itself. Not available on every car, but where it is, it can be compared with the dashboard.")
        case 0x14...0x1B: return Loc.t(
            "Напряжение кислородного датчика. Верхний датчик (S1) на исправном моторе быстро колеблется между 0.1 и 0.9 В — это признак живой обратной связи. Нижний (S2) должен стоять почти ровно: если он тоже колеблется, катализатор не работает.",
            "Oxygen sensor voltage. A healthy upstream sensor (S1) swings rapidly between 0.1 and 0.9 V — that is live feedback. The downstream sensor (S2) should stay nearly flat: if it swings too, the catalyst is not working.")
        case 0x24...0x2B, 0x34...0x3B: return Loc.t(
            "Широкополосный кислородный датчик: показывает состав смеси числом. Единица — идеальное соотношение, больше единицы — бедная смесь, меньше — богатая.",
            "Wideband oxygen sensor: reports the mixture as a number. One means the ideal ratio, above one is lean, below one is rich.")
        default: return nil
        }
    }
}

// MARK: - Оценка относительно нормы

enum Norms {

    static func assess(pid: UInt8, value: Double, context c: EngineContext) -> NormAssessment? {
        switch pid {

        // --- Температура охлаждающей жидкости ---
        case 0x05:
            let range = Loc.t("80–105 °C на прогретом двигателе", "80–105 °C when warmed up")
            if value > 110 {
                return NormAssessment(status: .high, rangeText: range,
                    meaning: Loc.t("Двигатель перегревается. Это состояние, при котором разрушаются прокладка головки и сама головка блока.",
                                   "The engine is overheating. This is the condition that destroys head gaskets and cylinder heads."),
                    whatToCheck: Loc.t("Немедленно заглушить. Уровень охлаждающей жидкости, термостат, вентилятор радиатора, помпа.",
                                       "Shut down immediately. Check coolant level, thermostat, radiator fan, water pump."))
            }
            if value > 105 {
                return NormAssessment(status: .high, rangeText: range,
                    meaning: Loc.t("Температура выше обычной рабочей.",
                                   "Temperature is above the usual operating range."),
                    whatToCheck: Loc.t("Понаблюдать: если продолжает расти — вентилятор или система охлаждения.",
                                       "Watch it: if it keeps rising, suspect the fan or the cooling system."))
            }
            if c.running, let t = c.coolantTemp, t < 70 {
                return NormAssessment(status: .low, rangeText: range,
                    meaning: Loc.t("Двигатель не вышел на рабочую температуру. Если так и остаётся после 10–15 минут работы — почти всегда термостат заклинил открытым.",
                                   "The engine has not reached operating temperature. If it stays like this after 10–15 minutes of running, the thermostat is almost always stuck open."),
                    whatToCheck: Loc.t("Термостат. Побочные признаки: слабая печка, повышенный расход.",
                                       "The thermostat. Side effects: weak cabin heat, higher fuel consumption."))
            }
            return NormAssessment(status: c.warmedUp ? .normal : .notApplicable, rangeText: range,
                meaning: c.warmedUp ? nil : Loc.t("Двигатель ещё прогревается — оценивать рано.",
                                                  "The engine is still warming up — too early to judge."),
                whatToCheck: nil)

        // --- Топливные коррекции ---
        case 0x06, 0x07, 0x08, 0x09:
            let isLongTerm = (pid == 0x07 || pid == 0x09)
            let range = Loc.t("от −10% до +10%", "−10% to +10%")
            let a = abs(value)
            if a < 10 {
                return NormAssessment(status: .normal, rangeText: range, meaning: nil, whatToCheck: nil)
            }
            let lean = value > 0
            let meaning = lean
                ? Loc.t("Блок вынужден добавлять топливо — значит воздуха приходит больше, чем он рассчитывает. Смесь бедная.",
                        "The ECU has to add fuel — more air is arriving than it expects. The mixture is lean.")
                : Loc.t("Блок вынужден убавлять топливо — его приходит больше, чем нужно. Смесь богатая.",
                        "The ECU has to cut fuel — more is arriving than needed. The mixture is rich.")
            let check = lean
                ? Loc.t("Подсос воздуха во впуске (шланги, прокладка, патрубки), загрязнённый расходомер, слабый бензонасос, забитый топливный фильтр, грязные форсунки.",
                        "Intake air leak (hoses, gasket, boots), contaminated MAF sensor, weak fuel pump, clogged fuel filter, dirty injectors.")
                : Loc.t("Льющие форсунки, завышенное давление топлива, забитый воздушный фильтр, неисправный кислородный датчик.",
                        "Leaking injectors, excessive fuel pressure, clogged air filter, failed oxygen sensor.")
            var extra = ""
            if isLongTerm && a >= 25 {
                extra = Loc.t(" Отклонение больше 25% — блок исчерпал запас регулировки, скоро появится ошибка по составу смеси.",
                              " A deviation over 25% means the ECU has run out of adjustment range; a mixture fault code will appear soon.")
            }
            return NormAssessment(status: lean ? .high : .low, rangeText: range,
                                  meaning: meaning + extra, whatToCheck: check)

        // --- Давление во впуске ---
        case 0x0B:
            if !c.running {
                return NormAssessment(status: .notApplicable,
                    rangeText: Loc.t("на заглушенном моторе ≈ атмосферное, около 100 кПа",
                                     "engine off ≈ atmospheric, about 100 kPa"),
                    meaning: Loc.t("Двигатель не работает, разрежения нет — это нормально.",
                                   "The engine is not running, so there is no vacuum — this is expected."),
                    whatToCheck: nil)
            }
            let range = Loc.t("20–45 кПа на прогретом холостом ходу", "20–45 kPa at warm idle")
            if c.atIdle && value > 50 {
                return NormAssessment(status: .high, rangeText: range,
                    meaning: Loc.t("Слишком слабое разрежение на холостых. Двигатель не может создать вакуум — значит воздух приходит мимо дросселя либо мотор плохо держит компрессию.",
                                   "Vacuum is too weak at idle. The engine cannot pull a vacuum — either air is bypassing the throttle or compression is poor."),
                    whatToCheck: Loc.t("Подсос воздуха, подклинивший дроссель, поздние фазы ГРМ, износ цилиндропоршневой группы.",
                                       "Air leak, sticking throttle, retarded valve timing, worn cylinders."))
            }
            if c.atIdle && value < 15 {
                return NormAssessment(status: .low, rangeText: range,
                    meaning: Loc.t("Очень сильное разрежение — часто признак забитого выпуска.",
                                   "Unusually strong vacuum — often a sign of a blocked exhaust."),
                    whatToCheck: Loc.t("Забитый катализатор или сажевый фильтр.",
                                       "Clogged catalytic converter or particulate filter."))
            }
            return NormAssessment(status: .normal, rangeText: range, meaning: nil, whatToCheck: nil)

        // --- Обороты ---
        case 0x0C:
            guard c.running else {
                return NormAssessment(status: .notApplicable,
                    rangeText: Loc.t("двигатель заглушен", "engine off"),
                    meaning: nil, whatToCheck: nil)
            }
            let range = Loc.t("650–900 об/мин на прогретом холостом ходу",
                              "650–900 rpm at warm idle")
            guard c.atIdle, c.warmedUp else {
                return NormAssessment(status: .notApplicable, rangeText: range,
                    meaning: Loc.t("Норма применима только на прогретом холостом ходу.",
                                   "The range only applies at warm idle."),
                    whatToCheck: nil)
            }
            if value > 1000 {
                return NormAssessment(status: .high, rangeText: range,
                    meaning: Loc.t("Повышенные обороты холостого хода на прогретом моторе.",
                                   "Idle speed is elevated on a warm engine."),
                    whatToCheck: Loc.t("Почти всегда подсос воздуха мимо дросселя; реже — залипший клапан холостого хода.",
                                       "Almost always unmetered air past the throttle; less often a stuck idle valve."))
            }
            if value < 600 {
                return NormAssessment(status: .low, rangeText: range,
                    meaning: Loc.t("Заниженные обороты — машина может глохнуть на светофорах.",
                                   "Idle is low — the car may stall at traffic lights."),
                    whatToCheck: Loc.t("Загрязнённый дроссельный узел, нагар, слабая компрессия, плохое топливо.",
                                       "Dirty throttle body, carbon buildup, weak compression, poor fuel."))
            }
            return NormAssessment(status: .normal, rangeText: range, meaning: nil, whatToCheck: nil)

        // --- Напряжение бортсети ---
        case 0x42:
            if c.running {
                let range = Loc.t("13.5–14.8 В при работающем двигателе",
                                  "13.5–14.8 V with the engine running")
                if value < 13.0 {
                    return NormAssessment(status: .low, rangeText: range,
                        meaning: Loc.t("Генератор не заряжает аккумулятор как следует. Со временем машина перестанет заводиться, а низкое напряжение само по себе вызывает ложные ошибки в разных блоках.",
                                       "The alternator is not charging properly. Eventually the car will not start, and low voltage by itself causes spurious faults in other modules."),
                        whatToCheck: Loc.t("Ремень генератора, сам генератор, реле-регулятор, окисленные клеммы и массы.",
                                           "Alternator belt, alternator, voltage regulator, corroded terminals and grounds."))
                }
                if value > 15.0 {
                    return NormAssessment(status: .high, rangeText: range,
                        meaning: Loc.t("Перезаряд. Кипятит аккумулятор и выводит из строя электронику.",
                                       "Overcharging. It boils the battery and damages electronics."),
                        whatToCheck: Loc.t("Реле-регулятор напряжения генератора.",
                                           "The alternator's voltage regulator."))
                }
                return NormAssessment(status: .normal, rangeText: range, meaning: nil, whatToCheck: nil)
            } else {
                let range = Loc.t("12.4–12.7 В на заглушенном двигателе",
                                  "12.4–12.7 V with the engine off")
                if value < 12.0 {
                    return NormAssessment(status: .low, rangeText: range,
                        meaning: Loc.t("Аккумулятор разряжен или изношен. Ниже 12.0 В — это примерно половина заряда и меньше.",
                                       "The battery is flat or worn. Below 12.0 V is roughly half charge or less."),
                        whatToCheck: Loc.t("Возраст аккумулятора, утечка тока, качество зарядки от генератора.",
                                           "Battery age, parasitic drain, charging quality."))
                }
                if value > 13.0 {
                    return NormAssessment(status: .high, rangeText: range,
                        meaning: Loc.t("Похоже, аккумулятор только что заряжали или двигатель всё же работает.",
                                       "Looks like the battery was just charged, or the engine is actually running."),
                        whatToCheck: nil)
                }
                return NormAssessment(status: .normal, rangeText: range, meaning: nil, whatToCheck: nil)
            }

        // --- Температура воздуха на впуске ---
        case 0x0F:
            let range = Loc.t("близко к забортной на холодном моторе",
                              "close to ambient on a cold engine")
            if let amb = c.ambientTemp, !c.running || !c.warmedUp {
                if value - amb > 25 {
                    return NormAssessment(status: .high, rangeText: range,
                        meaning: Loc.t("Воздух на впуске намного горячее забортного. Горячий воздух менее плотный — двигатель теряет мощность.",
                                       "Intake air is far hotter than ambient. Hot air is less dense, so the engine loses power."),
                        whatToCheck: Loc.t("Подсос горячего воздуха из моторного отсека, повреждённый воздуховод, забитый интеркулер.",
                                           "Hot engine-bay air being drawn in, damaged intake ducting, blocked intercooler."))
                }
            }
            return NormAssessment(status: .normal, rangeText: range, meaning: nil, whatToCheck: nil)

        // --- Дроссель ---
        case 0x11, 0x45:
            let range = Loc.t("0–15% на холостом ходу", "0–15% at idle")
            guard c.atIdle else {
                return NormAssessment(status: .notApplicable, rangeText: range, meaning: nil, whatToCheck: nil)
            }
            if value > 20 {
                return NormAssessment(status: .high, rangeText: range,
                    meaning: Loc.t("Заслонка приоткрыта сильнее обычного на холостом ходу.",
                                   "The throttle is open wider than usual at idle."),
                    whatToCheck: Loc.t("Загрязнение дроссельного узла, требуется чистка и адаптация; либо неверная калибровка датчика.",
                                       "A dirty throttle body needing cleaning and relearn, or a mis-calibrated sensor."))
            }
            return NormAssessment(status: .normal, rangeText: range, meaning: nil, whatToCheck: nil)

        // --- Расчётная нагрузка ---
        case 0x04, 0x43:
            let range = Loc.t("15–35% на холостом ходу", "15–35% at idle")
            guard c.atIdle, c.warmedUp else {
                return NormAssessment(status: .notApplicable, rangeText: range, meaning: nil, whatToCheck: nil)
            }
            if value > 45 {
                return NormAssessment(status: .high, rangeText: range,
                    meaning: Loc.t("Двигателю тяжело держать холостой ход — он работает с повышенной нагрузкой там, где должен отдыхать.",
                                   "The engine is struggling to hold idle — working harder than it should at rest."),
                    whatToCheck: Loc.t("Забитый выпуск, слабая компрессия, навесное оборудование под нагрузкой, поздние фазы ГРМ.",
                                       "Blocked exhaust, weak compression, accessories under load, retarded valve timing."))
            }
            return NormAssessment(status: .normal, rangeText: range, meaning: nil, whatToCheck: nil)

        // --- Атмосферное давление (проверка датчика) ---
        case 0x33:
            let range = Loc.t("95–103 кПа на уровне моря", "95–103 kPa at sea level")
            if value < 80 || value > 110 {
                return NormAssessment(status: value > 110 ? .high : .low, rangeText: range,
                    meaning: Loc.t("Значение неправдоподобно для равнины. Либо вы высоко в горах, либо датчик врёт.",
                                   "The value is implausible at low altitude. Either you are high in the mountains, or the sensor is lying."),
                    whatToCheck: Loc.t("Датчик атмосферного давления или датчик во впуске, который его подменяет.",
                                       "The barometric sensor, or the manifold sensor standing in for it."))
            }
            return NormAssessment(status: .normal, rangeText: range, meaning: nil, whatToCheck: nil)

        // --- Температура масла ---
        case 0x5C:
            let range = Loc.t("90–110 °C на прогретом двигателе", "90–110 °C when warmed up")
            if value > 125 {
                return NormAssessment(status: .high, rangeText: range,
                    meaning: Loc.t("Масло перегрето — оно теряет свойства и перестаёт защищать двигатель.",
                                   "The oil is overheated — it loses its properties and stops protecting the engine."),
                    whatToCheck: Loc.t("Система охлаждения, масляный радиатор, уровень и качество масла.",
                                       "Cooling system, oil cooler, oil level and quality."))
            }
            return NormAssessment(status: c.warmedUp ? .normal : .notApplicable, rangeText: range,
                                  meaning: nil, whatToCheck: nil)

        // --- Температура катализатора ---
        case 0x3C, 0x3D, 0x3E, 0x3F:
            let range = Loc.t("400–800 °C на прогретом двигателе", "400–800 °C when warmed up")
            guard c.running, c.warmedUp else {
                return NormAssessment(status: .notApplicable, rangeText: range, meaning: nil, whatToCheck: nil)
            }
            if value > 900 {
                return NormAssessment(status: .high, rangeText: range,
                    meaning: Loc.t("Катализатор перегрет. Обычно это значит, что в него попадает несгоревшее топливо и он выгорает изнутри.",
                                   "The catalyst is overheating. Usually unburnt fuel is reaching it and burning it out from the inside."),
                    whatToCheck: Loc.t("Пропуски воспламенения, богатая смесь, неисправные форсунки. Разбираться срочно — катализатор дорогой.",
                                       "Misfires, rich mixture, faulty injectors. Address it promptly — catalysts are expensive."))
            }
            if value < 250 {
                return NormAssessment(status: .low, rangeText: range,
                    meaning: Loc.t("Катализатор не разогревается — скорее всего, не работает.",
                                   "The catalyst is not heating up — most likely it is not working."),
                    whatToCheck: Loc.t("Разрушенный катализатор или вырезанная начинка.",
                                       "A collapsed catalyst, or one that has been gutted."))
            }
            return NormAssessment(status: .normal, rangeText: range, meaning: nil, whatToCheck: nil)

        // --- Заданный состав смеси ---
        case 0x44:
            let range = Loc.t("около 1.00 в замкнутом контуре", "about 1.00 in closed loop")
            if value > 1.05 {
                return NormAssessment(status: .high, rangeText: range,
                    meaning: Loc.t("Блок намеренно обедняет смесь.", "The ECU is deliberately leaning the mixture."),
                    whatToCheck: nil)
            }
            if value < 0.90 {
                return NormAssessment(status: .low, rangeText: range,
                    meaning: Loc.t("Блок сильно обогащает смесь. Нормально при прогреве и полном газе, ненормально на прогретом холостом ходу.",
                                   "The ECU is enriching heavily. Normal during warm-up and at full throttle, abnormal at warm idle."),
                    whatToCheck: c.atIdle && c.warmedUp
                        ? Loc.t("Кислородный датчик, датчик температуры, форсунки.",
                                "Oxygen sensor, temperature sensor, injectors.")
                        : nil)
            }
            return NormAssessment(status: .normal, rangeText: range, meaning: nil, whatToCheck: nil)

        // --- Пробег с горящим Check ---
        case 0x21:
            if value > 0 {
                return NormAssessment(status: .high,
                    rangeText: Loc.t("норма — 0 км", "normal is 0 km"),
                    meaning: Loc.t("Машина ездила с активной неисправностью.",
                                   "The car was driven with an active fault."),
                    whatToCheck: Loc.t("Чем больше пробег с горящей лампой, тем дольше проблему игнорировали.",
                                       "The larger the distance, the longer the problem was ignored."))
            }
            return NormAssessment(status: .normal, rangeText: Loc.t("норма — 0 км", "normal is 0 km"),
                                  meaning: nil, whatToCheck: nil)

        // --- Угол опережения зажигания ---
        case 0x0E:
            let range = Loc.t("5–20° на прогретом холостом ходу", "5–20° at warm idle")
            guard c.atIdle, c.warmedUp else {
                return NormAssessment(status: .notApplicable, rangeText: range, meaning: nil, whatToCheck: nil)
            }
            if value < 0 {
                return NormAssessment(status: .low, rangeText: range,
                    meaning: Loc.t("Зажигание сильно отведено назад. Блок так делает, когда слышит детонацию или не доверяет датчикам — машина едет вяло и много ест.",
                                   "Timing is heavily retarded. The ECU does this when it hears knock or distrusts its sensors — the car feels sluggish and drinks fuel."),
                    whatToCheck: Loc.t("Качество топлива, датчик детонации, нагар в камерах сгорания, перегрев.",
                                       "Fuel quality, knock sensor, combustion chamber carbon, overheating."))
            }
            return NormAssessment(status: .normal, rangeText: range, meaning: nil, whatToCheck: nil)

        default:
            return nil
        }
    }
}
