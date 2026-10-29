export const RESOLVE_NUMERIC_DIAL_STEPS = [0.01, 0.1, 1];
const ZONES = new Set(['Black', 'Dark', 'Shadow', 'Light', 'Highlight', 'Specular', 'Global']);

export function resolveNumericBindingError(binding) {
  if (binding == null) return null;
  if (!binding || typeof binding !== 'object' || Array.isArray(binding)) return 'Learned HDR binding must be an object.';
  if (binding.version !== 1 || !ZONES.has(binding.zone) || !['Exp', 'Sat'].includes(binding.readout)) return 'Learned HDR binding has an unsupported version, zone, or readout.';
  if (![binding.panelWidth, binding.panelHeight].every(value => Number.isFinite(value) && value > 10 && value <= 10000)
      || ![binding.anchorX, binding.anchorY].every(value => Number.isFinite(value) && value >= 0 && value <= 1)) return 'Learned HDR binding has invalid panel geometry.';
  if (!Array.isArray(binding.fingerprint) || binding.fingerprint.length < 3 || binding.fingerprint.length > 7
      || new Set(binding.fingerprint).size !== binding.fingerprint.length
      || !binding.fingerprint.includes(binding.zone)
      || !binding.fingerprint.every(zone => ZONES.has(zone))) return 'Learned HDR binding has an invalid HDR zone fingerprint.';
  return null;
}

export function isCurrentResolveNumericResponse(operation, current, result) {
  return Boolean(operation && current && result
    && operation.id === current.id
    && operation.generation === current.generation
    && result.id === operation.id);
}
