import { createRoot } from 'react-dom/client'
import { FingertipHero } from './FingertipHero'

const el = document.getElementById('heroDemo')
if (el) createRoot(el).render(<FingertipHero />)
