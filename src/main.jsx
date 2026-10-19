import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import StudioShell from './StudioShell.jsx'
import { AppProvider } from './context/AppContext.jsx'

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <AppProvider><StudioShell /></AppProvider>
  </StrictMode>,
)
