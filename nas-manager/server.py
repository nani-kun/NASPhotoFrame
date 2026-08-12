#!/usr/bin/env python3
import base64
import hmac
import json
import os
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

PORT = int(os.environ.get("PORT", "8787"))
IPAD_HOST = os.environ.get("IPAD_HOST", "192.168.1.100")
IPAD_USER = os.environ.get("IPAD_USER", "root")
ADMIN_USER = os.environ.get("ADMIN_USER", "admin")
ADMIN_PASSWORD = os.environ["ADMIN_PASSWORD"]
SSH_DIR = Path(os.environ.get("SSH_DIR", "/data/ssh"))
ADMIN_PASSWORD_FILE = Path(
    os.environ.get("ADMIN_PASSWORD_FILE", str(SSH_DIR.parent / "admin-password"))
)
INDEX = Path(__file__).with_name("index.html").read_bytes()

SSH_BASE = [
    "ssh", "-i", str(SSH_DIR / "id_rsa"),
    "-o", "BatchMode=yes",
    "-o", "ConnectTimeout=7",
    "-o", "ConnectionAttempts=1",
    "-o", "StrictHostKeyChecking=accept-new",
    "-o", f"UserKnownHostsFile={SSH_DIR / 'known_hosts'}",
    "-o", "HostKeyAlgorithms=+ssh-rsa",
    "-o", "PubkeyAcceptedAlgorithms=+ssh-rsa",
    f"{IPAD_USER}@{IPAD_HOST}",
]


def run_ipad(arguments, timeout=15):
    completed = subprocess.run(
        SSH_BASE + list(arguments), capture_output=True, text=True, timeout=timeout
    )
    output = completed.stdout.strip()
    if completed.returncode != 0:
        detail = completed.stderr.strip() or output or f"远程命令失败 ({completed.returncode})"
        raise RuntimeError(detail)
    return output


def read_json_output(arguments):
    output = run_ipad(arguments)
    return json.loads(output) if output else {"ok": True}


def current_admin_password():
    try:
        saved = ADMIN_PASSWORD_FILE.read_text().strip()
        if saved:
            return saved
    except FileNotFoundError:
        pass
    return ADMIN_PASSWORD


def save_admin_password(password):
    ADMIN_PASSWORD_FILE.parent.mkdir(parents=True, exist_ok=True)
    temporary = ADMIN_PASSWORD_FILE.with_suffix(".tmp")
    temporary.write_text(password + "\n")
    temporary.chmod(0o600)
    temporary.replace(ADMIN_PASSWORD_FILE)


class Handler(BaseHTTPRequestHandler):
    server_version = "iPadPhotoFrameManager/1.0"

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} - {fmt % args}", flush=True)

    def authorized(self):
        expected = "Basic " + base64.b64encode(
            f"{ADMIN_USER}:{current_admin_password()}".encode()
        ).decode()
        return hmac.compare_digest(self.headers.get("Authorization", ""), expected)

    def require_auth(self):
        if self.authorized():
            return True
        self.send_response(401)
        # HTTP header values must be Latin-1 encodable.  A Chinese realm makes
        # BaseHTTPRequestHandler abort the unauthenticated response before a
        # browser can show its Basic Auth dialog.
        self.send_header("WWW-Authenticate", 'Basic realm="iPad Photo Frame Manager"')
        self.send_header("Content-Length", "0")
        self.end_headers()
        return False

    def send_json(self, status, payload):
        data = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def read_json(self):
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > 65536:
            raise ValueError("请求体大小无效")
        return json.loads(self.rfile.read(length))

    def do_GET(self):
        if not self.require_auth():
            return
        path = urlparse(self.path).path
        if path == "/":
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(INDEX)))
            self.end_headers()
            self.wfile.write(INDEX)
            return
        if path == "/api/bootstrap":
            public_key = (SSH_DIR / "id_rsa.pub").read_text().strip()
            self.send_json(200, {"ok": True, "publicKey": public_key, "iPadHost": IPAD_HOST})
            return
        if path == "/api/status":
            try:
                display = read_json_output(["/usr/libexec/PFDisplayScheduler", "status"])
                battery = read_json_output(["/usr/libexec/PFChargeLimiter", "status"])
                self.send_json(200, {
                    "ok": True,
                    "display": display,
                    "battery": battery,
                })
            except Exception as error:
                self.send_json(503, {"ok": False, "error": str(error)})
            return
        if path == "/api/policy":
            try:
                policy = read_json_output(["/usr/libexec/PFDisplayScheduler", "policy"])
                self.send_json(200, {"ok": True, "policy": policy})
            except Exception as error:
                self.send_json(503, {"ok": False, "error": str(error)})
            return
        if path == "/api/settings":
            try:
                self.send_json(200, read_json_output(["/usr/libexec/PFRemoteControl", "get-settings"]))
            except Exception as error:
                self.send_json(503, {"ok": False, "error": str(error)})
            return
        if path == "/api/client-info":
            try:
                self.send_json(200, read_json_output(
                    ["/usr/libexec/PFRemoteControl", "get-client-info"]
                ))
            except Exception as error:
                self.send_json(503, {"ok": False, "error": str(error)})
            return
        self.send_json(404, {"ok": False, "error": "未找到该接口"})

    def do_POST(self):
        if not self.require_auth():
            return
        path = urlparse(self.path).path
        try:
            body = self.read_json()
            if path == "/api/admin-password":
                current = body.get("currentPassword", "")
                new_password = body.get("newPassword", "")
                if not hmac.compare_digest(current, current_admin_password()):
                    raise ValueError("当前密码不正确")
                if not isinstance(new_password, str) or len(new_password) < 10:
                    raise ValueError("新密码至少需要 10 个字符")
                if len(new_password) > 128:
                    raise ValueError("新密码不能超过 128 个字符")
                if hmac.compare_digest(current, new_password):
                    raise ValueError("新密码不能与当前密码相同")
                save_admin_password(new_password)
                self.send_json(200, {"ok": True})
                return
            if path == "/api/action":
                action = body.get("action")
                commands = {
                    "sleep": ["/usr/libexec/PFDisplayScheduler", "sleep"],
                    "wake": ["/usr/libexec/PFDisplayScheduler", "wake"],
                    "restart": ["/usr/bin/killall", "NASPhotoFrame"],
                }
                if action not in commands:
                    raise ValueError("未知操作")
                try:
                    run_ipad(commands[action])
                except RuntimeError as error:
                    # killall returns non-zero when the app was not running; wake it anyway.
                    if action != "restart":
                        raise error
                if action == "restart":
                    run_ipad(["/usr/libexec/PFDisplayScheduler", "wake"])
                self.send_json(200, {"ok": True})
                return
            if path == "/api/settings":
                encoded = base64.b64encode(
                    json.dumps(body, ensure_ascii=False, separators=(",", ":")).encode()
                ).decode()
                result = read_json_output(["/usr/libexec/PFRemoteControl", "set-settings", encoded])
                if not result.get("ok"):
                    raise RuntimeError(result.get("error", "保存失败"))
                try:
                    run_ipad(["/usr/bin/killall", "NASPhotoFrame"])
                except RuntimeError:
                    pass
                run_ipad(["/usr/libexec/PFDisplayScheduler", "wake"])
                self.send_json(200, result)
                return
            if path == "/api/policy":
                required = {
                    "wakeScheduleEnabled", "sleepScheduleEnabled",
                    "wakeHour", "wakeMinute", "sleepHour", "sleepMinute",
                    "chargeLimitEnabled", "chargeStartPercent",
                    "chargeStopPercent", "brightnessPercent",
                }
                if not required.issubset(body):
                    raise ValueError("定时与充电设置不完整")
                for name in ("wakeHour", "sleepHour"):
                    if not isinstance(body[name], int) or not 0 <= body[name] <= 23:
                        raise ValueError("小时必须在 0–23 之间")
                for name in ("wakeMinute", "sleepMinute"):
                    if not isinstance(body[name], int) or not 0 <= body[name] <= 59:
                        raise ValueError("分钟必须在 0–59 之间")
                start = body["chargeStartPercent"]
                stop = body["chargeStopPercent"]
                if not isinstance(start, int) or not isinstance(stop, int):
                    raise ValueError("充电阈值必须是整数")
                if not 20 <= start <= 90 or not 30 <= stop <= 95 or start >= stop:
                    raise ValueError("充电阈值需满足：20≤开始<停止≤95")
                brightness = body["brightnessPercent"]
                if not isinstance(brightness, int) or not 5 <= brightness <= 100:
                    raise ValueError("屏幕亮度必须在 5%–100% 之间")
                encoded = base64.b64encode(
                    json.dumps(body, ensure_ascii=False, separators=(",", ":")).encode()
                ).decode()
                run_ipad(["/usr/libexec/PFDisplayScheduler", "set-policy", encoded])
                display = read_json_output(["/usr/libexec/PFDisplayScheduler", "status"])
                if not display.get("locked", True):
                    try:
                        run_ipad(["/usr/bin/killall", "NASPhotoFrame"])
                    except RuntimeError:
                        pass
                    run_ipad(["/usr/bin/uiopen", "nasphotoframe://open"])
                # Restart the display daemon so a changed time is applied now;
                # launchd KeepAlive starts it again and recreates the wake event.
                try:
                    run_ipad(["/bin/launchctl", "stop", "com.wangxiaoxiang.pfdisplayscheduler"])
                except RuntimeError:
                    run_ipad(["/usr/libexec/PFDisplayScheduler", "schedule-wake"])
                self.send_json(200, {"ok": True})
                return
            self.send_json(404, {"ok": False, "error": "未找到该接口"})
        except (ValueError, json.JSONDecodeError) as error:
            self.send_json(400, {"ok": False, "error": str(error)})
        except subprocess.TimeoutExpired:
            self.send_json(504, {"ok": False, "error": "iPad 响应超时"})
        except Exception as error:
            self.send_json(502, {"ok": False, "error": str(error)})


if __name__ == "__main__":
    print(f"Listening on 0.0.0.0:{PORT}; iPad={IPAD_USER}@{IPAD_HOST}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
