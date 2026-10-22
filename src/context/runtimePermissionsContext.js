import { createContext } from 'react';

export const RuntimePermissionsContext = createContext({ accessibilityAccess: null, eventPostingAllowed: null, native: false, keepControlStrip: false, updateKeepControlStrip: null, controlStripBusy: false, layoutCapacity: null });
