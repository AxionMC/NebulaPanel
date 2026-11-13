<p align="center"><a href="https://github.com/AxionMC/NebulaPanel"><img src="https://raw.githubusercontent.com/AxionMC/NebulaPanel/main/frontend/src/assets/images/NebulaPanel-logo.svg" alt="NebulaPanel" width="300" /></a></p>

<h3 align="center">پنل کنترل سرور مجازی متن‌باز با پشتیبانی بومی از عامل‌های هوش مصنوعی</h3>

<p align="center">
  مورد اعتماد <strong>بیش از ۲,۰۰۰,۰۰۰</strong> کاربر خودمیزبان در سراسر جهان
</p>

<p align="center">
  <a href="https://www.apache.org/licenses/LICENSE-2.0"><img src="https://img.shields.io/badge/License-Apache%202.0-7B2CBF.svg" alt="License: Apache 2.0"></a>
  <a href="https://github.com/AxionMC/NebulaPanel/releases"><img src="https://img.shields.io/github/v/release/AxionMC/NebulaPanel" alt="انتشار گیت‌هاب"></a>
  <a href="https://github.com/AxionMC/NebulaPanel"><img src="https://img.shields.io/github/stars/AxionMC/NebulaPanel?color=%237B2CBF&style=flat-square" alt="ستاره‌ها"></a>
</p>

<p align="center">
  <a href="/README.md"><img alt="English" src="https://img.shields.io/badge/English-d9d9d9"></a>
  <a href="/docs/README.zh-Hans.md"><img alt="中文(简体)" src="https://img.shields.io/badge/中文(简体)-d9d9d9"></a>
  <a href="/docs/README.ja.md"><img alt="日本語" src="https://img.shields.io/badge/日本語-d9d9d9"></a>
  <a href="/docs/README.pt-br.md"><img alt="Português (Brasil)" src="https://img.shields.io/badge/Português (Brasil)-d9d9d9"></a>
  <a href="/docs/README.ar.md"><img alt="العربية" src="https://img.shields.io/badge/العربية-d9d9d9"></a>
  <a href="/docs/README.de.md"><img alt="Deutsch" src="https://img.shields.io/badge/Deutsch-d9d9d9"></a>
  <a href="/docs/README.es-es.md"><img alt="Español" src="https://img.shields.io/badge/Español-d9d9d9"></a>
  <a href="/docs/README.fr.md"><img alt="français" src="https://img.shields.io/badge/français-d9d9d9"></a>
  <a href="/docs/README.ko.md"><img alt="한국어" src="https://img.shields.io/badge/한국어-d9d9d9"></a>
  <a href="/docs/README.id.md"><img alt="Bahasa Indonesia" src="https://img.shields.io/badge/Bahasa Indonesia-d9d9d9"></a>
  <a href="/docs/README.zh-Hant.md"><img alt="中文(繁體)" src="https://img.shields.io/badge/中文(繁體)-d9d9d9"></a>
  <a href="/docs/README.tr.md"><img alt="Türkçe" src="https://img.shields.io/badge/Türkçe-d9d9d9"></a>
  <a href="/docs/README.ru.md"><img alt="Русский" src="https://img.shields.io/badge/Русский-d9d9d9"></a>
  <a href="/docs/README.ms.md"><img alt="Bahasa Melayu" src="https://img.shields.io/badge/Bahasa Melayu-d9d9d9"></a>
  <a href="/docs/README.fa.md"><img alt="Persian" src="https://img.shields.io/badge/%D9%81%D8%A7%D8%B1%D8%B3%DB%8C-d9d9d9"></a>
  <a href="/docs/README.lo.md"><img alt="ພາສາລາວ" src="https://img.shields.io/badge/%E0%BA%9E%E0%BA%B2%E0%BA%AA%E0%BA%B2%E0%BA%A5%E0%BA%B2%E0%BA%A7-d9d9d9"></a>
</p>

---

## NebulaPanel چیست؟

NebulaPanel یک پنل کنترل سرور مجازی مدرن و متن‌باز است — و تنها پنلی که **پشتیبانی بومی از عامل‌های هوش مصنوعی** دارد. مدل‌های Ollama را اجرا کنید، عامل‌های شخصی OpenClaw را مستقر کنید و کل مجموعه سرور خود را از یک رابط وب تمیز مدیریت کنید. بدون نیاز به حفظ کردن دستورات CLI.

👉 ویدیوی [معرفی ۲ دقیقه‌ای](https://www.youtube.com/watch?v=Jl_wqp-XA08) را تماشا کنید

## چرا NebulaPanel؟

| | NebulaPanel | cPanel / Plesk | aaPanel | Webmin |
|--|--------|----------------|---------|--------|
| رایگان و متن‌باز | ✅ | ❌ | جزئی | ✅ |
| محیط اجرای بومی عامل هوش مصنوعی | ✅ | ❌ | ❌ | ❌ |
| بازارچه برنامه‌های یک‌کلیکی | ✅ ۱۶۵+ برنامه | ❌ | ✅ | ❌ |
| رابط کاربری مدرن (پس از ۲۰۲۰) | ✅ | ❌ | جزئی | ❌ |
| مدیریت Docker / کانتینر | ✅ | ❌ | ❌ | ❌ |
| توسعه فعال | ✅ | ✅ | ✅ | کند |

## ویژگی‌های کلیدی

- **محیط اجرای عامل هوش مصنوعی**: مدل‌های LLM Ollama را مستقر کنید، عامل‌های شخصی OpenClaw را راه‌اندازی کنید و مصرف GPU را نظارت کنید — همه از داخل داشبورد. بدون نیاز به مدیریت پشته هوش مصنوعی جداگانه.
- **استقرار یک‌کلیکی وب‌سایت**: وب‌سایت‌های آماده تولید را با اتصال خودکار دامنه، تأمین گواهی SSL و پیکربندی Nginx راه‌اندازی کنید — بدون تنظیمات دستی.
- **بازارچه برنامه**: ۱۶۵+ برنامه متن‌باز معتبر (Nextcloud، Bitwarden، Umami، NocoBase و موارد دیگر) که با یک کلیک نصب و به‌روزرسانی می‌شوند.
- **مدیریت Docker و کانتینر**: کانتینرها، تصاویر، شبکه‌ها و حجم‌ها را از طریق رابط کاربری بصری ایجاد، شروع، متوقف و بررسی کنید — بدون نیاز به کار با CLI.
- **امنیت از ابتدا**: قوانین دیواره آتش، fail2ban، ایزوله‌سازی کانتینر، WAF و لاگ‌های حسابرسی — از روز اول پیکربندی و فعال هستند.
- **پشتیبان‌گیری و بازیابی**: پشتیبان‌گیری خودکار را به AWS S3، Cloudflare R2 یا ذخیره‌سازی محلی زمان‌بندی کنید. هر تصویر لحظه‌ای را با یک کلیک بازیابی کنید.

## شروع سریع

> **نیازمندی‌ها:** سرور مجازی لینوکس (Debian / Ubuntu / CentOS / Rocky)، ۱ گیگابایت رم، دسترسی به اینترنت.  
> حدود ۶۰ ثانیه زمان می‌برد.

```bash
git clone https://github.com/AxionMC/NebulaPanel.git && cd NebulaPanel && sudo bash scripts/install.sh
```

پس از نصب، `http://<your-server-ip>:<port>/<security-path>` را در مرورگر خود باز کنید.  
در صورت نیاز به دریافت اطلاعات ورود، دستور `npctl user-info` را از طریق SSH اجرا کنید.

## تاریخچه ستاره

[![نمودار تاریخچه ستاره](https://api.star-history.com/svg?repos=AxionMC/NebulaPanel&type=Date)](https://star-history.com/#AxionMC/NebulaPanel&Date)

## انجمن و پشتیبانی

- **مستندات** — [Docs](https://github.com/AxionMC/NebulaPanel/blob/main/BUILD.md)
- **مشکلات** — [مشکلات گیت‌هاب](https://github.com/AxionMC/NebulaPanel/issues) برای گزارش باگ

## امنیت

آسیب‌پذیری پیدا کردید؟ لطفاً قبل از افشا، [SECURITY.md](/SECURITY.md) را مطالعه کنید.

## License

Licensed under the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).

Copyright (c) 2026 NebulaPanel contributors. All rights reserved.
