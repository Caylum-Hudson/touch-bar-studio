const clamp = value => Math.max(0, Math.min(255, Math.round(value)));
const parseHex = value => {
  const hex = /^#?([0-9a-f]{6})$/i.exec(value || '')?.[1];
  if (!hex) return [20, 21, 29];
  return [0, 2, 4].map(index => parseInt(hex.slice(index, index + 2), 16));
};
const toHex = rgb => `#${rgb.map(channel => clamp(channel).toString(16).padStart(2, '0')).join('')}`;
const mix = (color, target, amount) => toHex(parseHex(color).map((channel, index) => channel * (1 - amount) + target[index] * amount));
const luminance = color => parseHex(color).map(value => value / 255).map(value => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4).reduce((sum, value, index) => sum + value * [0.2126, 0.7152, 0.0722][index], 0);
const contrast = (a, b) => {
  const [lighter, darker] = [luminance(a), luminance(b)].sort((first, second) => second - first);
  return (lighter + 0.05) / (darker + 0.05);
};
const foreground = color => contrast(color, '#000000') >= contrast(color, '#ffffff') ? '#000000' : '#ffffff';
const contrastColor = (color, background) => contrast(color, background) >= 4.5 ? color : foreground(background);
const readableAccent = (accent, background) => {
  if (contrast(accent, background) >= 4.5) return accent;
  const target = foreground(background) === '#000000' ? [0, 0, 0] : [255, 255, 255];
  for (let amount = 0.1; amount <= 1; amount += 0.1) {
    const adjusted = mix(accent, target, amount);
    if (contrast(adjusted, background) >= 4.5) return adjusted;
  }
  return toHex(target);
};
const hue = color => {
  const [red, green, blue] = parseHex(color).map(value => value / 255);
  const max = Math.max(red, green, blue), min = Math.min(red, green, blue), delta = max - min;
  if (!delta) return 0;
  const raw = max === red ? (green - blue) / delta : max === green ? (blue - red) / delta + 2 : (red - green) / delta + 4;
  return (raw * 60 + 360) % 360;
};

export function themeTokens(background, accent) {
  const bg = /^#(?:[0-9a-f]{6})$/i.test(background || '') ? background : '#14151d';
  const primary = /^#(?:[0-9a-f]{6})$/i.test(accent || '') ? accent : '#a78bfa';
  const textColor = foreground(bg);
  const light = textColor === '#171820';
  const target = light ? [0, 0, 0] : [255, 255, 255];
  const accentText = foreground(primary);
  return {
    '--studio-bg': bg,
    '--studio-surface': mix(bg, target, light ? 0.045 : 0.11),
    '--studio-surface-raised': mix(bg, target, light ? 0.085 : 0.17),
    '--studio-input': mix(bg, target, light ? 0.025 : 0.07),
    '--studio-text': textColor,
    '--studio-muted': contrastColor(light ? '#626572' : '#b9bac4', bg),
    '--studio-border': light ? '#17182030' : '#ffffff24',
    '--studio-accent': primary,
    '--studio-accent-text-color': readableAccent(primary,bg),
    '--studio-accent-soft': `${primary}24`,
    '--studio-accent-border': `${primary}80`,
    '--studio-accent-text': accentText,
    '--studio-primary-text': accentText,
    '--studio-accent-icon-rotation': `${Math.round(hue(primary) - 265)}deg`,
  };
}
