"""
Эмулятор ELM327 + ЭБУ автомобиля.

Прикидывается Wi-Fi ELM327-донглом: слушает TCP-порт и отвечает так же,
как настоящий адаптер (эхо, формат строк, multi-frame для длинных ответов,
приглашение '>').

Нужен, чтобы отлаживать всю логику приложения без машины и без железа.

Запуск:
    python3 mock_ecu.py                 # "подозрительная" машина (по умолчанию)
    python3 mock_ecu.py --profile clean  # здоровая машина
"""

import argparse
import socket
import threading

PROMPT = b"\r\r>"


# ---------------------------------------------------------------------------
# Профили машин
# ---------------------------------------------------------------------------

def profile_suspicious():
    """Свежепроданная машина: ошибки стёрли час назад, пропуски в 3-м цилиндре."""
    return {
        "name": "suspicious",
        "vin": "KMHSH81XDCU123456",     # Hyundai Santa Fe
        "cal_id": "SHSJ4A16A0P",
        "cvn": "AB12CD34",
        # Mode 01 PID -> байты ответа (без заголовка 41 <pid>)
        "pids": {
            0x00: "BE 3F A8 13",   # поддерживаются 01-20, есть продолжение
            0x20: "80 03 A0 01",   # 21, 2F, 30, 31, 33 + продолжение
            0x40: "44 0C 80 11",   # 42, 46, 4D, 4E, 51, 5C + продолжение
            0x60: "00 00 00 01",   # ничего, но цепочка продолжается
            0x80: "00 00 00 01",
            0x01: "00 07 E1 E1",   # MIL off, 0 DTC, мониторы НЕ готовы
            0x03: "02 00",
            0x04: "45",            # нагрузка 27%
            0x05: "7D",            # ОЖ 85 C -- прогрет
            0x06: "94",            # STFT b1 +15.6%
            0x07: "9E",            # LTFT b1 +23.4%  <- сильный уход
            0x0B: "23",            # разрежение на холостых, 35 кПа
            0x0C: "0A F8",         # 702 об/мин
            0x0D: "00",
            0x0E: "80",
            0x0F: "3C",            # IAT 20 C
            0x10: "01 90",         # MAF 4.0 g/s
            0x11: "1F",
            0x1F: "00 96",         # 150 с с запуска
            0x21: "00 00",
            0x2F: "80",
            0x30: "01",            # 1 прогрев с момента сброса      <- улика
            0x31: "00 0C",         # 12 км с момента сброса ошибок   <- улика
            0x33: "65",
            0x42: "36 B0",         # 14.0 В
            0x46: "3C",            # за бортом 20 C
            0x4D: "00 00",
            0x4E: "00 17",         # 23 минуты с момента сброса      <- улика
            0x51: "01",            # бензин
            0x5C: "55",
            0xA0: "04 00 00 00",   # поддерживается A6 (одометр)
            0xA6: "00 27 8D 00",   # одометр 259 200 км
        },
        # стоп-кадр: условия в момент возникновения ошибки
        "freeze": {
            0x02: "03 03",         # код, из-за которого сохранён кадр (P0303)
            0x04: "5B",
            0x05: "58",
            0x0B: "38",
            0x0C: "07 D0",         # 500 об/мин -- провал при пропуске
            0x0D: "23",
            0x0E: "76",
            0x0F: "3A",
            0x10: "02 1C",
            0x11: "2A",
        },
        # OBDCOND, IGNCNTR, затем пары «завершено / условий» по мониторам
        "ipt": [9800, 11500,
                420, 9100,     # катализатор банк 1
                0, 0,          # катализатор банк 2 (нет)
                880, 9100,     # лямбды банк 1
                0, 0,
                760, 8900,     # EGR
                0, 0,          # вторичный воздух (нет)
                240, 8700],    # адсорбер
        "dtc_stored": [],
        "dtc_pending": ["P0303"],
        "dtc_permanent": ["P0303"],
        # счётчики пропусков зажигания по цилиндрам (Mode 06)
        "misfire": {1: 2, 2: 0, 3: 147, 4: 1},
    }


def profile_clean():
    """Здоровая машина с честной историей."""
    p = profile_suspicious()
    pids = dict(p["pids"])
    pids.update({
        0x01: "00 07 E1 00",   # все мониторы готовы
        0x05: "5A",            # 50 -> прогрет ниже, поправим ниже
        0x06: "80",            # STFT 0%
        0x07: "84",            # LTFT +3.1%
        0x30: "2A",            # 42 прогрева с момента сброса
        0x31: "12 34",         # 4660 км с момента сброса
        0x4E: "0B B8",         # 3000 минут
    })
    pids[0x05] = "78"          # 80 C -- двигатель прогрет
    p.update({
        "name": "clean",
        "pids": pids,
        "dtc_pending": [],
        "dtc_permanent": [],
        "freeze": {},
        "misfire": {1: 0, 2: 1, 3: 0, 4: 0},
    })
    return p


PROFILES = {"suspicious": profile_suspicious, "clean": profile_clean}


# ---------------------------------------------------------------------------
# Кодирование ответов
# ---------------------------------------------------------------------------

def encode_dtc(code):
    """'P0303' -> (0x03, 0x03) в формате двух байт DTC по SAE J2012."""
    letters = {"P": 0, "C": 1, "B": 2, "U": 3}
    hi = (letters[code[0]] << 6) | (int(code[1]) << 4) | int(code[2], 16)
    lo = int(code[3:5], 16)
    return hi, lo


def frames(payload):
    """
    Форматирует ответ так же, как настоящий ELM327 на CAN.

    Короткий ответ (<= 7 байт) -- одной строкой.
    Длинный -- строкой с общей длиной, затем пронумерованные кадры '0:', '1:'...
    """
    if len(payload) <= 7:
        return " ".join(f"{b:02X}" for b in payload)

    lines = [f"{len(payload):03X}"]
    idx, pos = 0, 0
    while pos < len(payload):
        take = 6 if idx == 0 else 7
        chunk = payload[pos:pos + take]
        lines.append(f"{idx}: " + " ".join(f"{b:02X}" for b in chunk))
        pos += take
        idx += 1
    return "\r".join(lines)


def dtc_response(mode, codes):
    payload = [mode + 0x40, len(codes)]
    for c in codes:
        payload.extend(encode_dtc(c))
    if not codes:
        payload = [mode + 0x40, 0x00]
    return frames(payload)


def mode06_response(mid, count):
    """
    Результат теста Mode 06: MID = номер цилиндра, TID 0x0B -- счётчик пропусков.
    46 <MID> <TID> <scaling> <val_hi> <val_lo> <min_hi> <min_lo> <max_hi> <max_lo>
    """
    payload = [0x46, mid, 0x0B, 0x24,
               (count >> 8) & 0xFF, count & 0xFF,
               0x00, 0x00, 0x00, 0xFF]
    return frames(payload)


# ---------------------------------------------------------------------------
# Логика адаптера
# ---------------------------------------------------------------------------

class MockAdapter:
    def __init__(self, profile):
        self.p = profile
        self.echo = True
        self.headers = False

    def handle(self, line):
        cmd = line.replace(" ", "").upper()
        if not cmd:
            return None

        if cmd.startswith("AT"):
            return self._at(cmd[2:])
        return self._obd(cmd)

    def _at(self, cmd):
        if cmd.startswith("Z") or cmd.startswith("WS"):
            self.echo = True
            return "ELM327 v1.5"
        if cmd.startswith("E"):
            self.echo = cmd[1:] == "1"
            return "OK"
        if cmd.startswith("H"):
            self.headers = cmd[1:] == "1"
            return "OK"
        if cmd == "DPN":
            return "6"          # ISO 15765-4 CAN 11bit/500k
        if cmd == "DP":
            return "ISO 15765-4 (CAN 11/500)"
        if cmd == "RV":
            return "14.0V"
        if cmd.startswith("I"):
            return "ELM327 v1.5"
        return "OK"

    def _obd(self, cmd):
        mode = cmd[:2]

        if mode == "01":
            pid = int(cmd[2:4], 16)
            data = self.p["pids"].get(pid)
            if data is None:
                return "NO DATA"
            payload = [0x41, pid] + [int(b, 16) for b in data.split()]
            return frames(payload)

        if mode == "03":
            return dtc_response(0x03, self.p["dtc_stored"])
        if mode == "07":
            return dtc_response(0x07, self.p["dtc_pending"])
        if mode == "0A":
            return dtc_response(0x0A, self.p["dtc_permanent"])

        if mode == "04":
            self.p["dtc_stored"] = []
            self.p["dtc_pending"] = []
            self.p["pids"][0x31] = "00 00"
            self.p["pids"][0x4E] = "00 00"
            self.p["pids"][0x01] = "00 07 E1 E1"
            return "44"

        if mode == "02":
            pid = int(cmd[2:4], 16)
            frame = int(cmd[4:6], 16) if len(cmd) >= 6 else 0
            data = self.p.get("freeze", {}).get(pid)
            if data is None or frame != 0:
                return "NO DATA"
            payload = [0x42, pid, frame] + [int(b, 16) for b in data.split()]
            return frames(payload)

        if mode == "06":
            mid = int(cmd[2:4], 16)
            if mid == 0x00:
                # какие тесты поддерживаются: MID 01..04
                return frames([0x46, 0x00, 0xF0, 0x00, 0x00, 0x00])
            count = self.p["misfire"].get(mid)
            if count is None:
                return "NO DATA"
            return mode06_response(mid, count)

        if mode == "09":
            pid = int(cmd[2:4], 16)
            if pid == 0x02:
                payload = [0x49, 0x02, 0x01] + [ord(c) for c in self.p["vin"]]
                return frames(payload)
            if pid == 0x04:
                payload = [0x49, 0x04, 0x01] + [ord(c) for c in self.p["cal_id"]]
                return frames(payload)
            if pid == 0x06:
                payload = [0x49, 0x06, 0x01] + [int(self.p["cvn"][i:i + 2], 16)
                                                for i in range(0, 8, 2)]
                return frames(payload)
            if pid == 0x08:
                # счётчики наработки: OBDCOND, IGNCNTR, затем пары по мониторам
                values = self.p.get("ipt", [])
                if not values:
                    return "NO DATA"
                payload = [0x49, 0x08, len(values)]
                for v in values:
                    payload += [(v >> 8) & 0xFF, v & 0xFF]
                return frames(payload)
            return "NO DATA"

        return "NO DATA"


def serve_client(conn, profile):
    adapter = MockAdapter(profile)
    buf = b""
    try:
        while True:
            chunk = conn.recv(1024)
            if not chunk:
                return
            buf += chunk
            while b"\r" in buf:
                raw, buf = buf.split(b"\r", 1)
                line = raw.decode("ascii", "ignore").strip()
                reply = adapter.handle(line)
                if reply is None:
                    conn.sendall(PROMPT)
                    continue
                out = b""
                if adapter.echo:
                    out += line.encode() + b"\r"
                out += reply.encode() + PROMPT
                conn.sendall(out)
    except (ConnectionResetError, BrokenPipeError):
        pass
    finally:
        conn.close()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--profile", default="suspicious", choices=list(PROFILES))
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=35000)
    args = ap.parse_args()

    profile = PROFILES[args.profile]()
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((args.host, args.port))
    srv.listen(5)
    print(f"Эмулятор ELM327 [{profile['name']}] на {args.host}:{args.port}")
    print("Ctrl+C для остановки")

    try:
        while True:
            conn, addr = srv.accept()
            print(f"  подключение с {addr[0]}:{addr[1]}")
            threading.Thread(target=serve_client, args=(conn, profile),
                             daemon=True).start()
    except KeyboardInterrupt:
        print("\nостановлен")
    finally:
        srv.close()


if __name__ == "__main__":
    main()
