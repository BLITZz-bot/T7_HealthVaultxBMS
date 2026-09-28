import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
import { configErrors } from './config/env';
import { ConfigErrorPage } from './pages/PlaceholderPages';
import './index.css';

createRoot(document.getElementById('root')!).render(
  <StrictMode>{configErrors.length ? <ConfigErrorPage errors={configErrors} /> : <App />}</StrictMode>,
);
