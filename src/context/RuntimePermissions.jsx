import { createContext, useContext } from 'react';

const RuntimePermissionsContext = createContext({ accessibilityAccess: null, eventPostingAllowed: null, native: false });

export function RuntimePermissionsProvider({ accessibilityAccess, eventPostingAllowed, native, children }) {
  return (
    <RuntimePermissionsContext.Provider value={{ accessibilityAccess, eventPostingAllowed, native }}>
      {children}
    </RuntimePermissionsContext.Provider>
  );
}

export function useRuntimePermissions() {
  return useContext(RuntimePermissionsContext);
}
