const DATE_TOKENS = {
  EEEE: 'Wednesday', EEE: 'Wednesday', MMMM: 'September', MMM: 'September',
  yyyy: '8888', yy: '88', MM: '12', M: '12', dd: '31', d: '31',
  HH: '23', H: '23', hh: '12', h: '12', mm: '59', ss: '59', aa: 'PM', a: 'PM', A: 'PM',
};

export function formatTimePreview(format = 'HH:mm', timeZone) {
  const quotedMatch = format.match(/^'([^']*)'[\s]+(.*)/);
  const prefix = quotedMatch?.[1] || '';
  const actualFormat = quotedMatch?.[2] || format;
  let now;
  if (timeZone && timeZone.trim()) {
    const parts = new Intl.DateTimeFormat('en-US', {timeZone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hour12:false}).formatToParts(new Date());
    const values = Object.fromEntries(parts.filter(part=>part.type!=='literal').map(part=>[part.type,part.value]));
    now = new Date(`${values.year}-${values.month}-${values.day}T${values.hour}:${values.minute}:${values.second}`);
  } else now = new Date();
  const h24=now.getHours(), h12=h24%12||12, minutes=now.getMinutes(), seconds=now.getSeconds();
  const components={
    EEEE:['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'][now.getDay()],
    EEE:['Sun','Mon','Tue','Wed','Thu','Fri','Sat'][now.getDay()],
    MMMM:['January','February','March','April','May','June','July','August','September','October','November','December'][now.getMonth()],
    MMM:['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][now.getMonth()],
    yyyy:String(now.getFullYear()), yy:String(now.getFullYear()).slice(-2),
    MM:String(now.getMonth()+1).padStart(2,'0'), M:String(now.getMonth()+1),
    dd:String(now.getDate()).padStart(2,'0'), d:String(now.getDate()),
    HH:String(h24).padStart(2,'0'), H:String(h24), hh:String(h12).padStart(2,'0'), h:String(h12),
    mm:String(minutes).padStart(2,'0'), ss:String(seconds).padStart(2,'0'),
    aa:h24>=12?'pm':'am', a:h24>=12?'pm':'am', A:h24>=12?'PM':'AM',
  };
  const tokenPattern=/EEEE|EEE|MMMM|MMM|yyyy|yy|MM|M(?!M)|dd|d(?!d)|HH|H(?!H)|hh|h(?!h)|mm|ss|aa|a|A/g;
  const text=actualFormat.replace(tokenPattern,token=>components[token]);
  return prefix ? `${prefix} ${text}` : text;
}

export function longestDateText(format = 'HH:mm') {
  const prefixMatch = String(format).match(/^'([^']*)'\s+(.*)$/);
  const prefix = prefixMatch?.[1] || '';
  const template = prefixMatch?.[2] || String(format);
  const tokens = /EEEE|EEE|MMMM|MMM|yyyy|yy|MM|M|dd|d|HH|H|hh|h|mm|ss|aa|a|A/g;
  const dateText = template.replace(tokens, token => DATE_TOKENS[token]);
  return prefix ? `${prefix} ${dateText}` : dateText;
}

export function estimateTouchBarTextWidth(text) {
  return Array.from(String(text)).reduce((width, character) => {
    if (/\s/.test(character)) return width + 3.5;
    if (/[MW@%]/.test(character)) return width + 8;
    if (/[A-Z0-9]/.test(character)) return width + 7;
    if (/[a-z]/.test(character)) return width + (/[iljtfr]/.test(character) ? 4 : 6.5);
    if (/[-.,:;!|'"()]/.test(character)) return width + 4;
    return width + 13;
  }, 0);
}

const textWidth = (text, icon = false, padding = 24) =>
  Math.ceil(estimateTouchBarTextWidth(text) + padding + (icon ? 22 : 0));

/** Conservative preview width for native text/status controls whose view width is intrinsic. */
export function widgetContentWidth(item) {
  if (!item || item.image?.base64) return null;
  if (item.title?.trim()) return textWidth(item.title);
  switch (item.type) {
    case 'timeButton': {
      const format=item.formatTemplate || 'HH:mm';
      return Math.max(textWidth(formatTimePreview(format,item.timeZone), true),textWidth(longestDateText(format),true));
    }
    // The Studio shell uses an 18px icon, 4px gap, 20px horizontal item
    // padding, plus a small font-variation allowance.
    case 'cpu': return textWidth('100%', true, 30);
    case 'ramUsage': return textWidth('100%', true, 30);
    case 'gpuUsage': return textWidth('100%', true, 30);
    case 'boardTemperature': return textWidth('Board —', false, 52);
    case 'cpuTemperature': return textWidth('130°C', true, 30);
    case 'battery': return textWidth('100% 999:59', true, 16);
    case 'weather': return textWidth('☀ 999°F', true, 16);
    case 'yandexWeather': return textWidth('☀ 999°', true, 16);
    case 'currency': return textWidth(`${item.from || 'BTC'}999999.99`);
    case 'music': return textWidth('Song title — Artist', true, 16);
    case 'network': return textWidth('↓999 MB/s ↑999 MB/s', false, 16);
    case 'inputsource': return textWidth('Extended Keyboard', true, 16);
    case 'upnext': return textWidth('Calendar event title · 12:59', false, 16);
    case 'pomodoro': return textWidth('Focus 99:59', true, 16);
    case 'group': return textWidth(`${item.title || 'Group'} 99`, false, 20);
    case 'staticButton': return textWidth(item.title || 'Button');
    case 'appleScriptTitledButton':
    case 'shellScriptTitledButton': return textWidth(item.title || (item.type === 'appleScriptTitledButton' ? 'Script' : 'Shell'));
    default: return null;
  }
}
