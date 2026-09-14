/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        marca: 'var(--cor-primaria)',
        'marca-escura': 'var(--cor-secundaria)',
      },
    },
  },
  plugins: [],
}
