// MV3 service worker — proves the background host runs.
console.log('[Muninn Hello] background service worker started');
chrome.runtime.onInstalled?.addListener(() => console.log('[Muninn Hello] installed'));
