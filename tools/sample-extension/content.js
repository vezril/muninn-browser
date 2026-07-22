(function () {
  const bar = document.createElement('div');
  bar.textContent = '🐦‍⬛ Muninn Hello extension is running on ' + location.host;
  Object.assign(bar.style, {
    position: 'fixed', top: '0', left: '0', right: '0', zIndex: '2147483647',
    font: '13px -apple-system, system-ui, sans-serif', color: '#fff',
    background: 'linear-gradient(90deg,#6d5efc,#b06dfc)', padding: '6px 12px',
    textAlign: 'center', boxShadow: '0 1px 6px rgba(0,0,0,.3)'
  });
  document.documentElement.appendChild(bar);
})();
