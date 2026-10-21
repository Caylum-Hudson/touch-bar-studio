import { RuntimePermissionsContext } from './runtimePermissionsContext';

export function RuntimePermissionsProvider({ accessibilityAccess, eventPostingAllowed, native, keepControlStrip = false, updateKeepControlStrip, controlStripBusy = false, children }) {
  return (
    <RuntimePermissionsContext.Provider value={{ accessibilityAccess, eventPostingAllowed, native, keepControlStrip, updateKeepControlStrip, controlStripBusy }}>
      {children}
    </RuntimePermissionsContext.Provider>
  );
}
