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
    const saved = JSON.parse(localStorage.getItem('saved_artists') || '[]');
    this.pushEvent('load_saved_artists', { artists: saved });
    this.handleEvent('save_artists', ({ artists }) => {
      localStorage.setItem('saved_artists', JSON.stringify(artists));
    });
  },
};

Hooks.PersistUploadMode = {
  mounted() {
    const saved = localStorage.getItem('upload_mode');
    if (saved) {
      this.el.value = saved;
      this.pushEvent('set_upload_mode', { upload_mode: saved });
    }
    this.el.addEventListener('change', e => {
      localStorage.setItem('upload_mode', e.target.value);
    });
  },
};

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute('content');
const liveSocket = new LiveSocket('/live', Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
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

if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js');
  });
}
