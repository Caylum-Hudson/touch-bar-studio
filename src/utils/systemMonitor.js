export const SYSTEM_MONITOR_METRICS = ['cpu', 'gpu', 'memory', 'temperature'];

export const LEGACY_SYSTEM_METRIC_TYPES = {
  cpu: 'cpu',
  gpu: 'gpuUsage',
  memory: 'ramUsage',
  temperature: 'cpuTemperature',
};

export function selectedSystemMonitorMetrics(item) {
  const requested = item?.metrics;
  if (!Array.isArray(requested)) return [...SYSTEM_MONITOR_METRICS];
  return SYSTEM_MONITOR_METRICS.filter(metric => requested.includes(metric));
}

export function systemMonitorPreview(item) {
  if (typeof item?.runtimePreview?.title === 'string') return item.runtimePreview.title ? [item.runtimePreview.title] : [];
  const samples = {cpu:'100%',gpu:'100%',memory:'100%',temperature:'130°C'};
  return selectedSystemMonitorMetrics(item).map(metric => samples[metric]);
}
