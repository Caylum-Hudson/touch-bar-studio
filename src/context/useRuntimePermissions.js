import { useContext } from 'react';
import { RuntimePermissionsContext } from './runtimePermissionsContext';

export function useRuntimePermissions() {
  return useContext(RuntimePermissionsContext);
}
