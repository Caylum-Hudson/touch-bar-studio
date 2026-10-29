import { RuntimePermissionsContext } from './runtimePermissionsContext';

export function RuntimePermissionsProvider({ accessibilityAccess, eventPostingAllowed, native, keepControlStrip = false, updateKeepControlStrip, controlStripBusy = false, layoutCapacity = null, systemMonitorPreviews = [], activeStudioGroupPath = [], activeRuntimeProfile = null, activeRuntimeResolvePage = null, activeRuntimeEnabled = false, previewScalePercent = 100, updatePreviewScalePercent, children }) {
  return (
    <RuntimePermissionsContext.Provider value={{ accessibilityAccess, eventPostingAllowed, native, keepControlStrip, updateKeepControlStrip, controlStripBusy, layoutCapacity, systemMonitorPreviews, activeStudioGroupPath, activeRuntimeProfile, activeRuntimeResolvePage, activeRuntimeEnabled, previewScalePercent, updatePreviewScalePercent }}>
      {children}
    </RuntimePermissionsContext.Provider>
  );
}
