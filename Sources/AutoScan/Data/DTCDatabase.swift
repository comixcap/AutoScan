import Foundation

struct DTCEntry {
    let ru: String
    let en: String
    let ruWhy: String
    let enWhy: String
    let severity: DTCSeverity
}

/// База стандартных кодов OBD-II с объяснением «что это значит на самом деле».
/// Коды, которых здесь нет, расшифровываются по структуре — см. DTCDecoder.structural.
enum DTCDatabase {

    static let entries: [String: DTCEntry] = build()

    private static func build() -> [String: DTCEntry] {
        var d: [String: DTCEntry] = [:]

        func add(_ code: String, _ ru: String, _ en: String,
                 _ ruWhy: String, _ enWhy: String, _ sev: DTCSeverity) {
            d[code] = DTCEntry(ru: ru, en: en, ruWhy: ruWhy, enWhy: enWhy, severity: sev)
        }

        // MARK: Фазовращатели, ГРМ, подогрев лямбд

        add("P0011", "Опережение распредвала, банк 1", "Camshaft timing over-advanced, bank 1",
            "Фазовращатель встал не в то положение. Частые причины: грязное масло, забитый клапан VVT, растянутая цепь ГРМ. Симптомы — плавающие обороты, потеря тяги.",
            "Variable valve timing is off target. Usually dirty oil, a clogged VVT solenoid or a stretched timing chain. Symptoms: rough idle, power loss.", .serious)
        add("P0014", "Опережение распредвала, банк 1 (выпуск)", "Exhaust camshaft timing over-advanced, bank 1",
            "То же, что P0011, но по выпускному валу. Начинать проверку с уровня и состояния масла и с клапана VVT.",
            "Same as P0011 but on the exhaust cam. Start with oil level/condition and the VVT solenoid.", .serious)
        add("P0016", "Рассогласование коленвала и распредвала", "Crankshaft / camshaft correlation, bank 1",
            "Метки ГРМ разошлись. Очень часто — растянутая цепь или проскочивший ремень. Ездить с этим опасно: возможна встреча клапанов с поршнями.",
            "Crank and cam are out of sync. Commonly a stretched chain or slipped belt. Risky to drive — valves can meet pistons.", .critical)
        add("P0017", "Рассогласование коленвала и распредвала (выпуск)", "Crank / cam correlation, bank 1 exhaust",
            "См. P0016. Проверять натяжитель и растяжение цепи ГРМ.",
            "See P0016. Inspect the chain tensioner and chain stretch.", .critical)
        add("P0030", "Цепь подогрева лямбда-зонда B1S1", "O2 heater control circuit B1S1",
            "Не работает подогрев верхнего кислородного датчика. Обычно сам датчик или его проводка/предохранитель. На езду влияет слабо, но растёт расход.",
            "The upstream oxygen sensor heater is not working. Usually the sensor itself, wiring or a fuse. Minor drivability impact, higher fuel use.", .warning)
        add("P0031", "Подогрев лямбды B1S1: низкий уровень", "O2 heater circuit low B1S1",
            "Обрыв или замыкание на массу в цепи подогрева датчика. Чаще всего меняется сам датчик.",
            "Open or short to ground in the sensor heater circuit. Usually the sensor is replaced.", .warning)
        add("P0032", "Подогрев лямбды B1S1: высокий уровень", "O2 heater circuit high B1S1",
            "Замыкание на плюс в цепи подогрева. Проверить проводку до датчика.",
            "Short to power in the heater circuit. Check wiring to the sensor.", .warning)
        add("P0036", "Цепь подогрева лямбда-зонда B1S2", "O2 heater control circuit B1S2",
            "Подогрев нижнего (послекатализаторного) датчика. На работу двигателя почти не влияет, но техосмотр не пройти.",
            "Heater on the post-catalyst sensor. Almost no drivability effect, but it fails emissions testing.", .warning)
        add("P0050", "Цепь подогрева лямбда-зонда B2S1", "O2 heater control circuit B2S1",
            "То же, что P0030, но по второму блоку цилиндров (V-образные и оппозитные моторы).",
            "Same as P0030 but on bank 2 (V and boxer engines).", .warning)

        // MARK: Смесь, датчики воздуха

        add("P0100", "Цепь датчика расхода воздуха (MAF)", "Mass air flow circuit",
            "Блок не видит корректного сигнала расходомера. Часто — грязный MAF, подсос воздуха после него или окисленный разъём.",
            "The ECU is not getting a valid MAF signal. Often a dirty MAF, an air leak after it, or a corroded connector.", .serious)
        add("P0101", "Расходомер: сигнал вне диапазона", "MAF circuit range / performance",
            "Расходомер врёт. Классика: загрязнённая нить MAF, порванный патрубок, забитый воздушный фильтр. Один из главных виновников «пропала тяга».",
            "The MAF reads implausibly. Classic causes: contaminated sensor element, split intake hose, clogged air filter. A leading cause of power loss complaints.", .serious)
        add("P0102", "Расходомер: низкий сигнал", "MAF circuit low input",
            "Сигнал ниже нормы — обычно загрязнение датчика или обрыв в проводке.",
            "Signal below range — usually sensor contamination or an open circuit.", .serious)
        add("P0103", "Расходомер: высокий сигнал", "MAF circuit high input",
            "Сигнал выше нормы. Проверить проводку и герметичность впуска.",
            "Signal above range. Check wiring and intake sealing.", .serious)
        add("P0106", "Датчик давления во впуске (MAP): диапазон", "MAP sensor range / performance",
            "Показания датчика давления не совпадают с расчётными. Подсос воздуха, забитая трубка датчика или неисправный MAP.",
            "Manifold pressure reading disagrees with expected. Vacuum leak, blocked sensor port, or a failed MAP sensor.", .serious)
        add("P0107", "MAP: низкий сигнал", "MAP circuit low input",
            "Обрыв в проводке датчика давления или сам датчик.",
            "Open circuit in the MAP wiring, or the sensor itself.", .serious)
        add("P0108", "MAP: высокий сигнал", "MAP circuit high input",
            "Замыкание на плюс или отсоединённая вакуумная трубка.",
            "Short to power or a disconnected vacuum line.", .serious)
        add("P0110", "Цепь датчика температуры воздуха", "Intake air temperature circuit",
            "Проблема с датчиком температуры впускного воздуха. Влияет на смесеобразование, особенно на холодную.",
            "Fault in the intake air temperature sensor. Affects mixture, especially on cold starts.", .warning)
        add("P0111", "Датчик температуры воздуха: диапазон", "IAT sensor range / performance",
            "Датчик даёт неправдоподобные значения — часто просто состарился.",
            "The sensor reports implausible values — often simply aged out.", .warning)
        add("P0112", "Датчик температуры воздуха: низкий сигнал", "IAT circuit low",
            "Замыкание в цепи датчика температуры воздуха.",
            "Short in the IAT sensor circuit.", .warning)
        add("P0113", "Датчик температуры воздуха: высокий сигнал", "IAT circuit high",
            "Обрыв в цепи или отсоединённый разъём датчика.",
            "Open circuit or an unplugged sensor connector.", .warning)
        add("P0115", "Цепь датчика температуры ОЖ", "Engine coolant temperature circuit",
            "Проблема с датчиком температуры охлаждающей жидкости. Мотор может лить лишнее топливо и плохо заводиться.",
            "Fault in the coolant temperature sensor. The engine may over-fuel and start poorly.", .serious)
        add("P0116", "Датчик температуры ОЖ: диапазон", "ECT sensor range / performance",
            "Показания температуры неправдоподобны. Бывает при неисправном термостате или воздушной пробке.",
            "Coolant temperature reading is implausible. Can also mean a stuck thermostat or air pocket.", .warning)
        add("P0117", "Датчик температуры ОЖ: низкий сигнал", "ECT circuit low",
            "Замыкание в цепи датчика температуры ОЖ.",
            "Short in the ECT sensor circuit.", .warning)
        add("P0118", "Датчик температуры ОЖ: высокий сигнал", "ECT circuit high",
            "Обрыв в цепи датчика температуры ОЖ.",
            "Open circuit in the ECT sensor wiring.", .warning)
        add("P0120", "Цепь датчика положения дросселя", "Throttle position sensor circuit",
            "Блок не понимает положение дроссельной заслонки. Может уйти в аварийный режим с зажатой мощностью.",
            "The ECU can't read throttle position. May trigger limp mode with reduced power.", .serious)
        add("P0121", "Датчик дросселя: диапазон", "TPS range / performance",
            "Сигнал дросселя не соответствует остальным данным. Часто помогает чистка дроссельного узла.",
            "Throttle signal disagrees with other data. Cleaning the throttle body often helps.", .serious)
        add("P0122", "Датчик дросселя: низкий сигнал", "TPS circuit low",
            "Обрыв или замыкание на массу в цепи датчика дросселя.",
            "Open or short to ground in the TPS circuit.", .serious)
        add("P0123", "Датчик дросселя: высокий сигнал", "TPS circuit high",
            "Замыкание на плюс в цепи датчика дросселя.",
            "Short to power in the TPS circuit.", .serious)
        add("P0128", "Термостат: двигатель не выходит на температуру", "Coolant thermostat below regulating temperature",
            "Двигатель долго не прогревается — почти всегда заклинивший открытым термостат. Растёт расход, салон плохо греется.",
            "The engine takes too long to warm up — almost always a thermostat stuck open. Higher fuel use, weak cabin heat.", .warning)
        add("P0130", "Цепь лямбда-зонда B1S1", "O2 sensor circuit B1S1",
            "Неисправность верхнего кислородного датчика — того, по которому мотор строит смесь.",
            "Fault in the upstream oxygen sensor — the one the engine uses to trim the mixture.", .serious)
        add("P0131", "Лямбда B1S1: низкое напряжение", "O2 sensor circuit low voltage B1S1",
            "Датчик показывает бедную смесь постоянно. Может быть и подсос воздуха, а не сам датчик.",
            "The sensor reads permanently lean. Could be an air leak rather than the sensor itself.", .serious)
        add("P0132", "Лямбда B1S1: высокое напряжение", "O2 sensor circuit high voltage B1S1",
            "Датчик показывает богатую смесь. Проверить давление топлива и форсунки.",
            "The sensor reads permanently rich. Check fuel pressure and injectors.", .serious)
        add("P0133", "Лямбда B1S1: медленный отклик", "O2 sensor slow response B1S1",
            "Датчик состарился и реагирует вяло. Обычно меняется, ресурс порядка 100–150 тыс. км.",
            "The sensor has aged and responds slowly. Usually replaced; typical life 100–150k km.", .warning)
        add("P0134", "Лямбда B1S1: нет активности", "O2 sensor no activity detected B1S1",
            "Датчик молчит. Либо умер, либо оборвана проводка.",
            "The sensor is silent — dead sensor or broken wiring.", .serious)
        add("P0135", "Подогрев лямбды B1S1", "O2 sensor heater circuit B1S1",
            "Не греется верхний датчик, поэтому долго не входит в рабочий режим.",
            "The upstream sensor heater is dead, so it takes too long to start working.", .warning)
        add("P0136", "Цепь лямбда-зонда B1S2", "O2 sensor circuit B1S2",
            "Нижний датчик за катализатором. Влияет на диагностику катализатора, не на тягу.",
            "The post-catalyst sensor. Affects catalyst diagnostics, not power.", .warning)
        add("P0137", "Лямбда B1S2: низкое напряжение", "O2 circuit low voltage B1S2",
            "Нижний датчик показывает бедную смесь — часто из-за прогара выпускного тракта перед ним.",
            "Post-cat sensor reads lean — often an exhaust leak upstream of it.", .warning)
        add("P0138", "Лямбда B1S2: высокое напряжение", "O2 circuit high voltage B1S2",
            "Нижний датчик показывает богатую смесь либо закоротил.",
            "Post-cat sensor reads rich, or the circuit is shorted.", .warning)
        add("P0140", "Лямбда B1S2: нет активности", "O2 no activity detected B1S2",
            "Нижний датчик не подаёт признаков жизни.",
            "The post-catalyst sensor shows no activity.", .warning)
        add("P0141", "Подогрев лямбды B1S2", "O2 heater circuit B1S2",
            "Подогрев нижнего датчика. Частая и недорогая неисправность.",
            "Post-catalyst sensor heater. Common and inexpensive fault.", .warning)
        add("P0150", "Цепь лямбда-зонда B2S1", "O2 sensor circuit B2S1",
            "То же, что P0130, но второй блок цилиндров.",
            "Same as P0130 but bank 2.", .serious)
        add("P0171", "Слишком бедная смесь, банк 1", "System too lean, bank 1",
            "Воздуха больше, чем топлива. Топ причин: подсос воздуха во впуске, грязный MAF, слабый бензонасос, забитый фильтр, грязные форсунки. Один из самых частых кодов вообще.",
            "Too much air for the fuel. Top causes: intake air leak, dirty MAF, weak fuel pump, clogged filter, dirty injectors. One of the most common codes overall.", .serious)
        add("P0172", "Слишком богатая смесь, банк 1", "System too rich, bank 1",
            "Топлива больше, чем нужно. Причины: грязный воздушный фильтр, льющие форсунки, высокое давление топлива, умерший датчик кислорода.",
            "Too much fuel. Causes: clogged air filter, leaking injectors, high fuel pressure, failed oxygen sensor.", .serious)
        add("P0174", "Слишком бедная смесь, банк 2", "System too lean, bank 2",
            "См. P0171, второй блок цилиндров. Если вместе с P0171 — ищите общую причину: подсос или расходомер.",
            "See P0171, bank 2. Together with P0171 it points to a shared cause: an air leak or the MAF.", .serious)
        add("P0175", "Слишком богатая смесь, банк 2", "System too rich, bank 2",
            "См. P0172, второй блок цилиндров.",
            "See P0172, bank 2.", .serious)
        add("P0190", "Датчик давления в топливной рампе", "Fuel rail pressure sensor circuit",
            "Проблема с датчиком давления топлива. На дизелях и GDI — причина потери тяги и тяжёлого запуска.",
            "Fuel rail pressure sensor fault. On diesels and GDI engines it causes power loss and hard starting.", .serious)

        // MARK: Форсунки, турбина

        add("P0201", "Цепь форсунки, цилиндр 1", "Injector circuit cylinder 1",
            "Обрыв или замыкание в цепи форсунки первого цилиндра. Цилиндр не работает.",
            "Open or short in cylinder 1 injector circuit. That cylinder is dead.", .serious)
        for cyl in 2...8 {
            add("P020\(cyl)",
                "Цепь форсунки, цилиндр \(cyl)",
                "Injector circuit cylinder \(cyl)",
                "Обрыв или замыкание в цепи форсунки цилиндра \(cyl) — цилиндр не получает топливо и не работает. Проверяют разъём, проводку и сопротивление обмотки форсунки.",
                "Open or short in the cylinder \(cyl) injector circuit — that cylinder gets no fuel and is dead. Check the connector, wiring and injector coil resistance.",
                .serious)
        }
        add("P0217", "Перегрев двигателя", "Engine over temperature condition",
            "Двигатель перегрелся. Останавливаться и глушить: перегрев убивает прокладку ГБЦ и головку.",
            "The engine overheated. Stop and shut down: overheating destroys head gaskets and cylinder heads.", .critical)
        add("P0234", "Превышение наддува", "Turbocharger overboost condition",
            "Турбина даёт больше давления, чем нужно. Заклинивший вестгейт, порванная трубка управления или неисправный актуатор.",
            "The turbo is producing more boost than commanded. Stuck wastegate, split control hose or failed actuator.", .serious)
        add("P0299", "Недостаточный наддув", "Turbocharger underboost",
            "Наддува не хватает — отсюда «нет тяги». Причины: утечки в интеркулере и патрубках, закисший актуатор геометрии, износ турбины.",
            "Boost is below target — the classic 'no power' complaint. Causes: leaks in intercooler piping, seized VNT actuator, worn turbo.", .serious)

        // MARK: Пропуски зажигания и детонация

        add("P0300", "Пропуски воспламенения в случайных цилиндрах", "Random / multiple cylinder misfire",
            "Пропуски сразу в нескольких цилиндрах. Общая причина: слабое зажигание, подсос воздуха, низкое давление топлива, плохой бензин. Долгая езда с пропусками убивает катализатор.",
            "Misfires across several cylinders. Common causes: weak ignition, air leak, low fuel pressure, bad fuel. Driving on misfires destroys the catalytic converter.", .serious)
        add("P0301", "Пропуски воспламенения, цилиндр 1", "Cylinder 1 misfire detected",
            "Конкретный цилиндр не воспламеняет смесь. Проверяют по порядку: свеча, катушка, форсунка, компрессия. Если компрессия — это уже дорого.",
            "One cylinder is not firing. Check in order: spark plug, coil, injector, compression. If it's compression, that's the expensive one.", .serious)
        for cyl in 2...8 {
            add("P030\(cyl)",
                "Пропуски воспламенения, цилиндр \(cyl)",
                "Cylinder \(cyl) misfire detected",
                "Цилиндр \(cyl) не воспламеняет смесь. Проверяют по цепочке от дешёвого к дорогому: свеча, катушка, форсунка, компрессия. Если дело в компрессии — это уже ремонт двигателя. Долгая езда с пропусками разрушает катализатор.",
                "Cylinder \(cyl) is not firing. Check from cheapest to most expensive: spark plug, coil, injector, compression. If it is compression, that means engine repair. Driving on misfires destroys the catalytic converter.",
                .serious)
        }
        add("P0325", "Цепь датчика детонации, банк 1", "Knock sensor 1 circuit",
            "Блок не видит датчик детонации и на всякий случай зажимает опережение — отсюда вялый разгон и рост расхода.",
            "The ECU can't read the knock sensor and retards timing as a precaution — sluggish acceleration and higher fuel use.", .serious)
        add("P0327", "Датчик детонации: низкий сигнал", "Knock sensor 1 circuit low input",
            "Сигнал датчика детонации ниже нормы — сам датчик или проводка.",
            "Knock sensor signal below range — the sensor or its wiring.", .warning)
        add("P0335", "Цепь датчика положения коленвала", "Crankshaft position sensor circuit",
            "Главный датчик для запуска двигателя. Отказ = машина не заводится или глохнет на ходу.",
            "The primary sensor for running the engine. A failure means no start or stalling while driving.", .critical)
        add("P0336", "Датчик коленвала: диапазон", "CKP sensor range / performance",
            "Сигнал коленвала с провалами. Часто разрушенный задающий венец или стружка на датчике.",
            "Crank signal has dropouts. Often a damaged reluctor ring or metal debris on the sensor.", .serious)
        add("P0340", "Цепь датчика положения распредвала", "Camshaft position sensor circuit",
            "Мотор может не заводиться или заводиться со второго раза, возможны рывки.",
            "The engine may not start or start on the second try, with hesitation.", .serious)
        add("P0341", "Датчик распредвала: диапазон", "CMP sensor range / performance",
            "Сигнал распредвала не совпадает с коленвалом — проверять ГРМ.",
            "Cam signal disagrees with crank — inspect the timing drive.", .serious)

        // MARK: EGR, катализатор, адсорбер

        add("P0401", "Недостаточный поток EGR", "EGR flow insufficient",
            "Клапан рециркуляции забит нагаром — типично для дизелей и моторов с большим пробегом. Лечится чисткой или заменой клапана.",
            "The EGR valve is clogged with carbon — typical on diesels and high-mileage engines. Cleaning or replacing the valve fixes it.", .warning)
        add("P0402", "Избыточный поток EGR", "EGR flow excessive",
            "Клапан EGR не закрывается — неровный холостой ход, глохнет на светофоре.",
            "The EGR valve won't close — rough idle and stalling at lights.", .warning)
        add("P0403", "Цепь управления EGR", "EGR control circuit",
            "Электрическая часть клапана EGR: проводка или сам привод.",
            "The electrical side of the EGR valve: wiring or the actuator.", .warning)
        add("P0420", "Эффективность катализатора ниже порога, банк 1", "Catalyst efficiency below threshold, bank 1",
            "Катализатор не справляется. Но прежде чем менять (это дорого) — проверьте нижний лямбда-зонд и герметичность выпуска: очень часто виноваты они, а не катализатор.",
            "The catalytic converter is underperforming. Before replacing it (expensive) check the downstream O2 sensor and exhaust leaks — they are often the real cause.", .warning)
        add("P0421", "Эффективность прогревочного катализатора", "Warm-up catalyst efficiency, bank 1",
            "См. P0420 — по прогревочной секции катализатора.",
            "See P0420 — for the warm-up catalyst section.", .warning)
        add("P0430", "Эффективность катализатора ниже порога, банк 2", "Catalyst efficiency below threshold, bank 2",
            "См. P0420, второй блок цилиндров.", "See P0420, bank 2.", .warning)
        add("P0440", "Система улавливания паров топлива", "Evaporative emission system",
            "Утечка в системе паров бензина. Первое, что проверяют — плотно ли закручена крышка бензобака. Серьёзно только для техосмотра.",
            "A leak in the fuel vapour system. First thing to check is the fuel cap. Mostly matters for emissions testing.", .info)
        add("P0441", "Неверный поток продувки адсорбера", "Evap purge flow incorrect",
            "Клапан продувки адсорбера работает не так. На езду почти не влияет.",
            "The purge valve isn't flowing correctly. Little drivability impact.", .info)
        add("P0442", "Малая утечка в системе паров", "Evap system small leak detected",
            "Небольшая утечка. Начинают с крышки бака и патрубков — трещины в резине от возраста.",
            "A small leak. Start with the fuel cap and hoses — age-cracked rubber is typical.", .info)
        add("P0443", "Цепь клапана продувки адсорбера", "Evap purge control valve circuit",
            "Электрика клапана продувки. Если клапан завис открытым — плавают обороты.",
            "Purge valve electrics. A valve stuck open causes unstable idle.", .warning)
        add("P0455", "Большая утечка в системе паров", "Evap system large leak detected",
            "Крупная утечка. Чаще всего просто не закрыта или порвана прокладка крышки бензобака.",
            "A large leak. Most often just an open or torn-gasket fuel cap.", .info)
        add("P0456", "Очень малая утечка в системе паров", "Evap system very small leak",
            "Микроутечка паров. Крышка бака, реже — трещина в магистрали.",
            "A very small vapour leak. Fuel cap, sometimes a cracked line.", .info)
        add("P0480", "Цепь вентилятора охлаждения", "Cooling fan 1 control circuit",
            "Вентилятор радиатора. Опасно летом и в пробках — риск перегрева.",
            "Radiator fan circuit. Dangerous in summer traffic — overheating risk.", .serious)

        // MARK: Скорость, холостой ход, электрика

        add("P0500", "Датчик скорости автомобиля", "Vehicle speed sensor",
            "Блок не видит скорость. Может не работать спидометр, круиз, ABS-логика.",
            "The ECU can't read speed. Speedometer, cruise control and ABS logic may misbehave.", .warning)
        add("P0505", "Система холостого хода", "Idle air control system",
            "Обороты холостого хода не держатся. Часто помогает чистка дросселя и адаптация.",
            "Idle speed is not held. Throttle body cleaning and relearn often fixes it.", .warning)
        add("P0506", "Холостой ход ниже нормы", "Idle speed lower than expected",
            "Двигатель работает на слишком низких оборотах, может глохнуть. Грязный дроссель, подсос, нагар.",
            "The engine idles too low and may stall. Dirty throttle, air leak, carbon buildup.", .warning)
        add("P0507", "Холостой ход выше нормы", "Idle speed higher than expected",
            "Повышенные обороты холостого хода — почти всегда подсос воздуха мимо дросселя.",
            "Idle is too high — almost always unmetered air leaking past the throttle.", .warning)
        add("P0562", "Низкое напряжение бортсети", "System voltage low",
            "Питание ниже нормы. Проверить генератор, ремень, аккумулятор и массы. Может стать причиной множества «случайных» ошибок.",
            "Supply voltage is low. Check the alternator, belt, battery and ground straps. A frequent cause of random-looking faults.", .serious)
        add("P0563", "Высокое напряжение бортсети", "System voltage high",
            "Перезаряд — неисправное реле-регулятор генератора. Опасно для электроники.",
            "Overcharging — a failed voltage regulator. Harmful to electronics.", .serious)

        // MARK: Блок управления и связь

        add("P0600", "Ошибка обмена внутри блока управления", "Serial communication link",
            "Внутренняя ошибка связи ЭБУ. Проверяют питание, массы и разъёмы блока.",
            "Internal ECU communication fault. Check power, grounds and connectors.", .serious)
        add("P0601", "Ошибка памяти блока управления", "Internal control module memory checksum error",
            "Повреждена память ЭБУ. Иногда следствие неудачной прошивки. Часто требует ремонта или замены блока.",
            "ECU memory is corrupted. Sometimes a result of a failed flash. Often needs module repair or replacement.", .critical)
        add("P0606", "Отказ процессора блока управления", "ECM/PCM processor fault",
            "Внутренний отказ блока управления двигателем.",
            "Internal failure of the engine control module.", .critical)
        add("P0700", "Запрос от блока управления коробкой", "Transmission control system malfunction",
            "Сам по себе ничего не говорит: это сигнал «у коробки есть свои ошибки». Их коды читаются только сканером с доступом к блоку АКПП.",
            "By itself it says nothing: it means 'the transmission module has its own codes'. Those require a scanner with transmission module access.", .serious)
        add("P0715", "Датчик оборотов входного вала АКПП", "Input / turbine speed sensor circuit",
            "Коробка не понимает скорость вращения. Возможны толчки и аварийный режим.",
            "The transmission can't read shaft speed. Expect harsh shifts or limp mode.", .serious)
        add("P0720", "Датчик оборотов выходного вала АКПП", "Output speed sensor circuit",
            "См. P0715, выходной вал.", "See P0715, output shaft.", .serious)
        add("P0730", "Неверное передаточное отношение", "Incorrect gear ratio",
            "Коробка не выходит на нужную передачу — проскальзывание. Для АКПП это серьёзно: уровень и состояние масла проверить немедленно.",
            "The transmission is not achieving the commanded ratio — slipping. Serious for an automatic: check fluid level and condition immediately.", .critical)
        add("P0741", "Муфта блокировки гидротрансформатора", "Torque converter clutch performance",
            "Блокировка гидротрансформатора буксует. Отсюда вибрация на ровной скорости и рост расхода.",
            "The torque converter lockup clutch is slipping. Causes vibration at steady speed and higher fuel use.", .serious)
        add("P0755", "Соленоид переключения B", "Shift solenoid B",
            "Электромагнитный клапан в гидроблоке АКПП. Часто лечится заменой соленоида или гидроблока, а не всей коробки.",
            "A solenoid in the valve body. Often fixed by replacing the solenoid or valve body rather than the whole transmission.", .serious)

        // MARK: P2xxx

        add("P2096", "Бедная смесь после катализатора, банк 1", "Post-catalyst fuel trim system too lean, bank 1",
            "Нижний датчик видит бедную смесь. Частая причина — прогар выпускного коллектора или трещина перед датчиком.",
            "The post-cat sensor reads lean. A common cause is an exhaust leak or crack ahead of the sensor.", .warning)
        add("P2097", "Богатая смесь после катализатора, банк 1", "Post-catalyst fuel trim too rich, bank 1",
            "Нижний датчик видит богатую смесь.",
            "The post-cat sensor reads rich.", .warning)
        add("P2101", "Привод дроссельной заслонки: диапазон", "Throttle actuator control motor range",
            "Электропривод дросселя работает не так, как ждёт блок. Возможен аварийный режим с зажатой мощностью.",
            "The electronic throttle actuator isn't behaving as commanded. May trigger reduced-power limp mode.", .serious)
        add("P2187", "Бедная смесь на холостом ходу, банк 1", "System too lean at idle, bank 1",
            "Подсос воздуха проявляется именно на холостых. Проверять впускные патрубки, прокладку впуска, вакуумные шланги.",
            "An air leak that shows up at idle. Check intake boots, manifold gasket and vacuum hoses.", .serious)
        add("P2270", "Лямбда B1S2 залипла на бедной", "O2 signal stuck lean, sensor 2 bank 1",
            "Нижний датчик залип. Обычно требуется замена датчика.",
            "The post-cat sensor is stuck. Usually needs replacement.", .warning)
        add("P2463", "Сажевый фильтр: накопление сажи", "Diesel particulate filter soot accumulation",
            "Забит сажевый фильтр. Нужна регенерация или чистка. Езда короткими поездками — прямая причина.",
            "The DPF is loaded with soot. Needs regeneration or cleaning. Short-trip driving is the direct cause.", .serious)

        // MARK: U-коды (сеть)

        add("U0001", "Шина CAN: общая неисправность", "High speed CAN communication bus",
            "Проблема на шине обмена между блоками. Часто окисленный разъём, повреждённая проводка или один «шумящий» блок.",
            "A fault on the inter-module communication bus. Often a corroded connector, damaged wiring, or one noisy module.", .serious)
        add("U0100", "Нет связи с блоком управления двигателем", "Lost communication with ECM/PCM",
            "Блоки перестали слышать ЭБУ двигателя. Проверить питание и массы блока, состояние разъёмов.",
            "Modules lost contact with the engine ECU. Check module power, grounds and connectors.", .critical)
        add("U0101", "Нет связи с блоком АКПП", "Lost communication with TCM",
            "Потеряна связь с блоком коробки передач.",
            "Lost communication with the transmission control module.", .serious)
        add("U0121", "Нет связи с блоком ABS", "Lost communication with ABS module",
            "Блок ABS не отвечает. Тормоза работают, но без ABS и стабилизации.",
            "The ABS module is not responding. Brakes work, but without ABS or stability control.", .serious)
        add("U0140", "Нет связи с блоком кузовной электроники", "Lost communication with body control module",
            "Не отвечает блок кузовной электроники — свет, замки, стеклоподъёмники.",
            "The body control module is not responding — lights, locks, windows.", .warning)
        add("U0155", "Нет связи с приборной панелью", "Lost communication with instrument cluster",
            "Приборная панель не на связи.",
            "The instrument cluster is off the bus.", .warning)

        return d
    }
}
