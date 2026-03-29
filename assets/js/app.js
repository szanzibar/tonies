// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import 'phoenix_html';
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from 'phoenix';
import { LiveSocket } from 'phoenix_live_view';
import topbar from '../vendor/topbar';

const Hooks = {};

Hooks.LongPress = {
  mounted() {
    this.timer = null;
    this.fired = false;
    const DELAY = 500;

    const start = (e) => {
      this.fired = false;
      this.timer = setTimeout(() => {
        this.fired = true;
        this.el.dispatchEvent(new Event('longpress', { bubbles: true }));
        this.pushEvent('long_press_chapter', { index: this.el.dataset.index });
        // Prevent the context menu on mobile after long press
        e.preventDefault();
      }, DELAY);
    };

    const cancel = () => {
      clearTimeout(this.timer);
    };

    const preventTap = (e) => {
      if (this.fired) {
        e.preventDefault();
        e.stopImmediatePropagation();
        this.fired = false;
      }
    };

    this.el.addEventListener('touchstart', start, { passive: false });
    this.el.addEventListener('touchend', cancel);
    this.el.addEventListener('touchmove', cancel);
    this.el.addEventListener('mousedown', start);
    this.el.addEventListener('mouseup', cancel);
    this.el.addEventListener('mouseleave', cancel);
    // Block the click that fires after a long press
    this.el.addEventListener('click', preventTap, { capture: true });
    this.el.addEventListener('contextmenu', (e) => e.preventDefault());
  },
};

Hooks.SavedArtists = {
  mounted() {
    this._loadSavedArtists();
    this._loadSavedPodcasts();
    this.handleEvent('save_artists', ({ artists }) => {
      localStorage.setItem('saved_artists', JSON.stringify(artists));
    });
    this.handleEvent('save_podcasts', ({ podcasts }) => {
      localStorage.setItem('saved_podcasts', JSON.stringify(podcasts));
    });
  },
  reconnected() {
    this._loadSavedArtists();
    this._loadSavedPodcasts();
  },
  _loadSavedArtists() {
    const saved = JSON.parse(localStorage.getItem('saved_artists') || '[]');
    this.pushEvent('load_saved_artists', { artists: saved });
  },
  _loadSavedPodcasts() {
    const saved = JSON.parse(localStorage.getItem('saved_podcasts') || '[]');
    this.pushEvent('load_saved_podcasts', { podcasts: saved });
  },
};

Hooks.LazyImages = {
  mounted() {
    this._loaded = new Set();
    this._setup();
  },
  updated() {
    // Restore src immediately for already-loaded images that LiveView may have
    // reverted to data-src during a DOM patch, so they don't visibly reload.
    this.el.querySelectorAll('img[data-src]').forEach(img => {
      if (this._loaded.has(img.dataset.src)) {
        img.src = img.dataset.src;
        img.removeAttribute('data-src');
      }
    });
    this._setup();
  },
  _setup() {
    if (this._timer) clearTimeout(this._timer);
    const images = Array.from(this.el.querySelectorAll('img[data-src]'));
    if (!images.length) return;
    let i = 0;
    const loadNext = () => {
      if (i >= images.length) return;
      const img = images[i++];
      if (img.dataset.src) {
        this._loaded.add(img.dataset.src);
        img.src = img.dataset.src;
        img.removeAttribute('data-src');
      }
      this._timer = setTimeout(loadNext, 75);
    };
    this._timer = setTimeout(loadNext, 10);
  },
  destroyed() {
    if (this._timer) clearTimeout(this._timer);
  },
};

Hooks.PersistUploadMode = {
  mounted() {
    this._restoreMode();
    this.el.addEventListener('change', e => {
      localStorage.setItem('upload_mode', e.target.value);
    });
  },
  reconnected() {
    this._restoreMode();
  },
  _restoreMode() {
    const saved = localStorage.getItem('upload_mode');
    if (saved) {
      this.el.value = saved;
      this.pushEvent('set_upload_mode', { upload_mode: saved });
    }
  },
};

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute('content');
const liveSocket = new LiveSocket('/live', Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
  reconnectAfterMs: (tries) => [200, 500, 1000, 2000, 5000][Math.min(tries - 1, 4)],
});

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: '#29d' }, shadowColor: 'rgba(0, 0, 0, .3)' });
window.addEventListener('phx:page-loading-start', _info => topbar.show(300));
window.addEventListener('phx:page-loading-stop', _info => topbar.hide());

// connect if there are any LiveViews on the page
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;

// PWA: auto-reload when returning from background if LiveView lost connection.
// Gives LiveView 2s to reconnect on its own, then does a clean page reload
// instead of showing the "Something went wrong" banner indefinitely.
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible') {
    setTimeout(() => {
      if (document.querySelector('.phx-client-error, .phx-server-error')) {
        window.location.reload();
      }
    }, 2000);
  }
});

if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js');
  });
}
