import { RuntimePermissionsContext } from './runtimePermissionsContext';

export function RuntimePermissionsProvider({ accessibilityAccess, eventPostingAllowed, native, keepControlStrip = false, updateKeepControlStrip, controlStripBusy = false, layoutCapacity = null, children }) {
  return (
    <RuntimePermissionsContext.Provider value={{ accessibilityAccess, eventPostingAllowed, native, keepControlStrip, updateKeepControlStrip, controlStripBusy, layoutCapacity }}>
      {children}
    </RuntimePermissionsContext.Provider>
  );
}
