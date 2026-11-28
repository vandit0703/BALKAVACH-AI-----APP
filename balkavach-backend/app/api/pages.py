"""Browser landing page for the password-reset email link.

The emailed link is ``PASSWORD_RESET_URL/?token=…`` (see ``app/integrations/email.py``). Point
``PASSWORD_RESET_URL`` at ``https://<api-host>/reset-password`` and this page completes the flow:
it reads the token from the URL, removes it from the address bar immediately, and submits the new
password to ``POST /api/v1/auth/password/reset`` (which consumes the single-use token and revokes
every session of the account).

Hardening: the token is never rendered into the HTML or logged by this route, responses are
``no-store`` with ``Referrer-Policy: no-referrer``, and a per-request nonce CSP allows only this
page's own script/style and same-origin requests.
"""

import json
import secrets

from fastapi import APIRouter, HTTPException
from fastapi.responses import HTMLResponse, JSONResponse

from app.core.config import settings

router = APIRouter(include_in_schema=False)

MIN_PASSWORD_LENGTH = 12

_STRINGS = {
	"en": {
		"title": "Reset your BALKAVACH password",
		"intro": "Choose a new password for your parent account.",
		"password": "New password",
		"confirm": "Confirm new password",
		"show": "Show",
		"hide": "Hide",
		"submit": "Save new password",
		"saving": "Saving…",
		"tooShort": "Use at least 12 characters.",
		"mismatch": "The two passwords do not match.",
		"missing": "This reset link is incomplete. Open the link from your email again, or request a new one in the app.",
		"invalid": "This reset link is invalid or has expired. Request a new one from the app.",
		"busy": "Too many attempts or the service is busy. Please try again in a few minutes.",
		"network": "Could not reach the server. Check your connection and try again.",
		"done": "Your password was changed. You have been signed out everywhere. Open the BALKAVACH app and sign in with the new password.",
	},
	"hi": {
		"title": "अपना BALKAVACH पासवर्ड रीसेट करें",
		"intro": "अपने पैरेंट खाते के लिए नया पासवर्ड चुनें।",
		"password": "नया पासवर्ड",
		"confirm": "नया पासवर्ड दोबारा लिखें",
		"show": "दिखाएँ",
		"hide": "छिपाएँ",
		"submit": "नया पासवर्ड सहेजें",
		"saving": "सहेजा जा रहा है…",
		"tooShort": "कम से कम 12 अक्षर रखें।",
		"mismatch": "दोनों पासवर्ड एक जैसे नहीं हैं।",
		"missing": "यह रीसेट लिंक अधूरा है। अपने ईमेल से लिंक फिर खोलें, या ऐप में नया लिंक मँगवाएँ।",
		"invalid": "यह रीसेट लिंक अमान्य है या समाप्त हो चुका है। ऐप से नया लिंक मँगवाएँ।",
		"busy": "बहुत अधिक प्रयास हुए हैं या सेवा व्यस्त है। कुछ मिनट बाद फिर कोशिश करें।",
		"network": "सर्वर तक नहीं पहुँच सके। अपना कनेक्शन जाँचें और फिर कोशिश करें।",
		"done": "आपका पासवर्ड बदल गया है और आप हर जगह साइन आउट हो गए हैं। BALKAVACH ऐप खोलकर नए पासवर्ड से साइन इन करें।",
	},
	"gu": {
		"title": "તમારો BALKAVACH પાસવર્ડ રીસેટ કરો",
		"intro": "તમારા પેરેન્ટ એકાઉન્ટ માટે નવો પાસવર્ડ પસંદ કરો.",
		"password": "નવો પાસવર્ડ",
		"confirm": "નવો પાસવર્ડ ફરી લખો",
		"show": "બતાવો",
		"hide": "છુપાવો",
		"submit": "નવો પાસવર્ડ સાચવો",
		"saving": "સાચવી રહ્યા છીએ…",
		"tooShort": "ઓછામાં ઓછા 12 અક્ષરો રાખો.",
		"mismatch": "બંને પાસવર્ડ સરખા નથી.",
		"missing": "આ રીસેટ લિંક અધૂરી છે. તમારા ઇમેઇલમાંથી લિંક ફરી ખોલો, અથવા એપમાં નવી લિંક મંગાવો.",
		"invalid": "આ રીસેટ લિંક અમાન્ય છે અથવા સમાપ્ત થઈ ગઈ છે. એપમાંથી નવી લિંક મંગાવો.",
		"busy": "ઘણા પ્રયાસો થયા છે અથવા સેવા વ્યસ્ત છે. થોડી મિનિટો પછી ફરી પ્રયાસ કરો.",
		"network": "સર્વર સુધી પહોંચી શકાયું નથી. તમારું કનેક્શન તપાસો અને ફરી પ્રયાસ કરો.",
		"done": "તમારો પાસવર્ડ બદલાઈ ગયો છે અને તમે બધે સાઇન આઉટ થઈ ગયા છો. BALKAVACH એપ ખોલીને નવા પાસવર્ડથી સાઇન ઇન કરો.",
	},
}

_PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<title>BALKAVACH</title>
<style nonce="__NONCE__">
:root{color-scheme:light dark;--bg:#f6f7fb;--fg:#1c1b1f;--card:#fff;--accent:#5b4bd5;--err:#b3261e;--ok:#146c2e;--line:#c9c5d0}
@media (prefers-color-scheme:dark){:root{--bg:#121316;--fg:#e6e1e5;--card:#1d1b20;--accent:#b8b0ff;--err:#f2b8b5;--ok:#8fd9a0;--line:#49454f}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.5 system-ui,sans-serif;display:flex;min-height:100vh;align-items:center;justify-content:center;padding:16px}
main{width:100%;max-width:440px;background:var(--card);border-radius:20px;padding:28px 24px;box-shadow:0 2px 14px rgba(0,0,0,.12)}
h1{font-size:1.35rem;margin:0 0 4px}p{margin:0 0 16px}label{display:block;font-weight:600;margin:14px 0 6px}
.row{display:flex;gap:8px}input{flex:1;min-width:0;font:inherit;padding:12px;border:1px solid var(--line);border-radius:12px;background:transparent;color:inherit}
button{font:inherit;border-radius:12px;border:0;padding:12px 16px;cursor:pointer;min-height:48px}
#submit{width:100%;margin-top:20px;background:var(--accent);color:#fff;font-weight:700}
#submit:disabled{opacity:.6;cursor:default}.toggle{background:transparent;border:1px solid var(--line);color:inherit;min-height:48px}
#message{margin-top:16px;font-weight:600}#message.err{color:var(--err)}#message.ok{color:var(--ok)}
</style>
</head>
<body>
<main>
<h1 id="title"></h1>
<p id="intro"></p>
<form id="form" novalidate autocomplete="off">
<label for="password" id="lblPassword"></label>
<div class="row"><input id="password" type="password" autocomplete="new-password" minlength="12" maxlength="128" required>
<button type="button" class="toggle" id="toggle1"></button></div>
<label for="confirm" id="lblConfirm"></label>
<div class="row"><input id="confirm" type="password" autocomplete="new-password" minlength="12" maxlength="128" required>
<button type="button" class="toggle" id="toggle2"></button></div>
<button id="submit" type="submit"></button>
</form>
<div id="message" role="alert" aria-live="polite"></div>
</main>
<script nonce="__NONCE__">
(function(){
var STRINGS=__STRINGS__;
var params=new URLSearchParams(location.search);
var lang=(params.get('lang')||navigator.language||'en').slice(0,2).toLowerCase();
var t=STRINGS[lang]||STRINGS.en;
document.documentElement.lang=STRINGS[lang]?lang:'en';
var token=params.get('token')||'';
// Remove the single-use token from the address bar/history right away.
if(token&&history.replaceState){history.replaceState(null,'',location.pathname)}
function $(id){return document.getElementById(id)}
$('title').textContent=t.title;document.title=t.title;$('intro').textContent=t.intro;
$('lblPassword').textContent=t.password;$('lblConfirm').textContent=t.confirm;$('submit').textContent=t.submit;
function wire(btn,input){btn.textContent=t.show;btn.setAttribute('aria-label',t.show);
btn.addEventListener('click',function(){var show=input.type==='password';input.type=show?'text':'password';
btn.textContent=show?t.hide:t.show;btn.setAttribute('aria-label',show?t.hide:t.show)})}
wire($('toggle1'),$('password'));wire($('toggle2'),$('confirm'));
function say(text,kind){var m=$('message');m.textContent=text;m.className=kind||''}
if(!token){say(t.missing,'err');$('submit').disabled=true}
$('form').addEventListener('submit',function(e){
e.preventDefault();if(!token)return;
var p=$('password').value,c=$('confirm').value;
if(p.length<__MIN__){say(t.tooShort,'err');return}
if(p!==c){say(t.mismatch,'err');return}
$('submit').disabled=true;$('submit').textContent=t.saving;say('');
fetch('/api/v1/auth/password/reset',{method:'POST',headers:{'Content-Type':'application/json'},
credentials:'omit',cache:'no-store',body:JSON.stringify({token:token,password:p})})
.then(function(r){
if(r.status===204){token='';$('form').hidden=true;say(t.done,'ok');return}
$('submit').disabled=false;$('submit').textContent=t.submit;
if(r.status===400){token='';say(t.invalid,'err');$('submit').disabled=true}
else if(r.status===422){say(t.tooShort,'err')}
else{say(t.busy,'err')}
}).catch(function(){$('submit').disabled=false;$('submit').textContent=t.submit;say(t.network,'err')});
});
})();
</script>
</body>
</html>
"""


def _headers(nonce: str) -> dict[str, str]:
	return {
		"Cache-Control": "no-store",
		"Pragma": "no-cache",
		"Referrer-Policy": "no-referrer",
		"X-Content-Type-Options": "nosniff",
		"X-Frame-Options": "DENY",
		"Content-Security-Policy": (
			"default-src 'none'; "
			f"script-src 'nonce-{nonce}'; style-src 'nonce-{nonce}'; "
			"connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
		),
	}


def render_reset_page() -> tuple[str, str]:
	nonce = secrets.token_urlsafe(16)
	html = (
		_PAGE.replace("__NONCE__", nonce)
		.replace("__MIN__", str(MIN_PASSWORD_LENGTH))
		.replace("__STRINGS__", json.dumps(_STRINGS, ensure_ascii=False).replace("</", "<\\/"))
	)
	return html, nonce


@router.get("/reset-password", response_class=HTMLResponse)
@router.get("/reset-password/", response_class=HTMLResponse)
def reset_password_page() -> HTMLResponse:
	html, nonce = render_reset_page()
	return HTMLResponse(content=html, headers=_headers(nonce))


@router.get("/.well-known/assetlinks.json", response_class=JSONResponse)
def android_asset_links() -> JSONResponse:
	"""Android App Links verification manifest (populated from ANDROID_ASSETLINKS_SHA256)."""
	fingerprints = [fp.strip() for fp in settings.android_assetlinks_sha256 if fp.strip()]
	if not fingerprints:
		raise HTTPException(status_code=404, detail="Android App Links not configured")
	payload = [
		{
			"relation": ["delegate_permission/common.handle_all_urls"],
			"target": {
				"namespace": "android_app",
				"package_name": settings.android_package_name,
				"sha256_cert_fingerprints": fingerprints,
			},
		}
	]
	return JSONResponse(
		content=payload,
		headers={"Cache-Control": "public, max-age=3600", "X-Content-Type-Options": "nosniff"},
	)
