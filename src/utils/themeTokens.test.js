import test from 'node:test';
import assert from 'node:assert/strict';
import {themeTokens} from './themeTokens.js';

const luminance = color => {
  const rgb = color.slice(1).match(/.{2}/g).map(value => parseInt(value,16)/255).map(value => value <= .04045 ? value/12.92 : ((value+.055)/1.055)**2.4);
  return rgb[0]*.2126+rgb[1]*.7152+rgb[2]*.0722;
};
const contrast = (first,second) => {
  const [light,dark]=[luminance(first),luminance(second)].sort((a,b)=>b-a);
  return (light+.05)/(dark+.05);
};

test('theme tokens follow the selected background and maintain readable foregrounds', () => {
  const light = themeTokens('#f2efdf', '#27a96b');
  assert.equal(light['--studio-bg'], '#f2efdf');
  assert.equal(light['--studio-text'], '#000000');
  assert.equal(light['--studio-primary-text'], '#000000');
  const dark = themeTokens('#10141c', '#d946ef');
  assert.equal(dark['--studio-bg'], '#10141c');
  assert.equal(dark['--studio-text'], '#ffffff');
  assert.equal(dark['--studio-primary-text'], '#000000');
  const paleAccent = themeTokens('#f2efdf','#f5ceeb');
  assert.ok(contrast(paleAccent['--studio-muted'],paleAccent['--studio-bg']) >= 4.5);
  assert.ok(contrast(paleAccent['--studio-accent-text-color'],paleAccent['--studio-bg']) >= 4.5);
  assert.ok(contrast(paleAccent['--studio-accent-text'],paleAccent['--studio-accent']) >= 4.5);
  const midtone = themeTokens('#777777','#315f49');
  assert.ok(contrast(midtone['--studio-text'],midtone['--studio-bg']) >= 4.5);
  assert.ok(contrast(midtone['--studio-muted'],midtone['--studio-bg']) >= 4.5);
  assert.ok(contrast(midtone['--studio-accent-text-color'],midtone['--studio-bg']) >= 4.5);
});
