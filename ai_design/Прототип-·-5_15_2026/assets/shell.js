// Compass+ — shared shell builder. Renders sidebar + tab bar + status bar
// around a per-screen <main>. Each screen calls Shell.mount(opts).
(function () {
  const ICONS = {
    folder: '<svg width="14" height="14" viewBox="0 0 16 16" fill="none"><path d="M1.5 4.5v7.5a1 1 0 0 0 1 1h11a1 1 0 0 0 1-1V6a1 1 0 0 0-1-1H8L6.5 3.5h-4a1 1 0 0 0-1 1Z" fill="currentColor"/></svg>',
    coll: '<svg width="14" height="14" viewBox="0 0 16 16" fill="none"><rect x="2.5" y="3" width="11" height="2.5" rx="0.6" fill="currentColor"/><rect x="2.5" y="6.5" width="11" height="2.5" rx="0.6" fill="currentColor" opacity="0.7"/><rect x="2.5" y="10" width="11" height="2.5" rx="0.6" fill="currentColor" opacity="0.45"/></svg>',
    search: '<svg width="14" height="14" viewBox="0 0 16 16" fill="none"><circle cx="7" cy="7" r="4.25" stroke="currentColor" stroke-width="1.4"/><path d="m10.3 10.3 3 3" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/></svg>',
    chev: '▸',
    plus: '<svg width="12" height="12" viewBox="0 0 12 12"><path d="M6 1.5v9M1.5 6h9" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/></svg>',
    close: '<svg width="10" height="10" viewBox="0 0 10 10"><path d="m1.5 1.5 7 7m0-7-7 7" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/></svg>',
    chevDown: '<svg width="10" height="10" viewBox="0 0 10 10"><path d="m2 3.5 3 3 3-3" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" fill="none"/></svg>',
    explorer: '<svg width="14" height="14" viewBox="0 0 16 16"><path d="M2 3h5l1.2 1.5H14V13a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V3Z" fill="currentColor" opacity="0.85"/></svg>',
    pipeline: '<svg width="14" height="14" viewBox="0 0 16 16" fill="none"><rect x="2" y="3" width="5" height="3.2" rx="0.8" fill="currentColor"/><rect x="9" y="6.4" width="5" height="3.2" rx="0.8" fill="currentColor"/><rect x="2" y="9.8" width="5" height="3.2" rx="0.8" fill="currentColor"/></svg>',
    schema: '<svg width="14" height="14" viewBox="0 0 16 16" fill="none"><circle cx="4" cy="4" r="1.8" fill="currentColor"/><circle cx="12" cy="4" r="1.8" fill="currentColor"/><circle cx="8" cy="11.5" r="1.8" fill="currentColor"/><path d="M4 4 8 11.5M12 4 8 11.5" stroke="currentColor" stroke-width="1.2"/></svg>',
    investigate: '<svg width="14" height="14" viewBox="0 0 16 16" fill="none"><path d="m7 2.5 1.5 3.4L12 6.7l-2.5 2.5.6 3.5L7 11l-3.1 1.7.6-3.5L2 6.7l3.5-.8L7 2.5Z" fill="currentColor"/></svg>',
    metrics: '<svg width="14" height="14" viewBox="0 0 16 16" fill="none"><rect x="2" y="9" width="2.4" height="5" fill="currentColor"/><rect x="6.8" y="6" width="2.4" height="8" fill="currentColor"/><rect x="11.6" y="3.5" width="2.4" height="10.5" fill="currentColor"/></svg>',
    shell: '<svg width="14" height="14" viewBox="0 0 16 16" fill="none"><rect x="1.5" y="3" width="13" height="10" rx="1.2" fill="currentColor" opacity="0.18"/><path d="m3.5 6 2 2-2 2M7 10h3.5" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" fill="none"/></svg>',
    dump: '<svg width="14" height="14" viewBox="0 0 16 16" fill="none"><path d="M8 2v7m0 0 2.4-2.4M8 9 5.6 6.6" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/><path d="M2.5 11v1.5a1 1 0 0 0 1 1h9a1 1 0 0 0 1-1V11" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" fill="none"/></svg>',
    log: '<svg width="14" height="14" viewBox="0 0 16 16" fill="none"><rect x="2.5" y="2.5" width="11" height="11" rx="1.3" fill="currentColor" opacity="0.15"/><path d="M5 6h6M5 8.5h6M5 11h3.5" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/></svg>',
  };

  const NAV_ITEMS = [
    { id: 'explorer',    label: 'Explorer',     icon: 'explorer'    },
    { id: 'aggregations',label: 'Aggregations', icon: 'pipeline'    },
    { id: 'schema',      label: 'Schema',       icon: 'schema'      },
    { id: 'investigate', label: 'Investigate',  icon: 'investigate' },
    { id: 'metrics',     label: 'Metrics',      icon: 'metrics'     },
    { id: 'shell',       label: 'Shell',        icon: 'shell'       },
    { id: 'dump',        label: 'Dump / Restore', icon: 'dump'      },
    { id: 'log',         label: 'Query Log',    icon: 'log'         },
  ];

  const DEFAULT_DBS = [
    { name: 'app_prod', size: '14.8 GB', open: true, collections: [
      { name: 'users',      count: '1.4M',  active: true  },
      { name: 'sessions',   count: '218K'  },
      { name: 'orders',     count: '4.2M'  },
      { name: 'invoices',   count: '912K'  },
      { name: 'audit_log',  count: '38.6M' },
    ]},
    { name: 'analytics',  size: '46.2 GB', collections: [] },
    { name: 'admin',      size: '128 KB',  collections: [] },
  ];

  const DEFAULT_TABS = [
    { db: 'app_prod', coll: 'users',    dotColor: '#16A34A' },
    { db: 'app_prod', coll: 'orders',   dotColor: '#16A34A' },
    { db: 'analytics',coll: 'events',   dotColor: '#2563EB' },
  ];

  function esc(s) { return String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }

  function renderSidebar(opts) {
    const cfg = Object.assign({
      connection: { name: 'production-cluster', host: 'mongodb+srv://app.5kx2.mongodb.net', status: 'success' },
      dbs: DEFAULT_DBS,
      activeNav: 'explorer',
      activeColl: { db: 'app_prod', coll: 'users' },
      searchValue: '',
    }, opts || {});

    const dbsHtml = cfg.dbs.map(db => {
      const isOpen = !!db.open;
      const collsHtml = isOpen ? db.collections.map(c => {
        const isActive = cfg.activeColl && cfg.activeColl.db === db.name && cfg.activeColl.coll === c.name;
        return `<div class="coll-row ${isActive ? 'is-active' : ''}" ${c.hover ? 'style="background:var(--surface-hover);"' : ''}>
          <span></span>
          <span class="coll-ico">${ICONS.coll}</span>
          <span class="mono" style="font-size:12px;">${esc(c.name)}</span>
          <span class="count-badge">${esc(c.count)}</span>
        </div>`;
      }).join('') : '';
      return `<div class="db-row ${isOpen ? 'is-open' : ''}">
          <span class="chev">${ICONS.chev}</span>
          <span class="db-ico">${ICONS.folder}</span>
          <span style="font-weight:600;">${esc(db.name)}</span>
          <span class="size-badge">${esc(db.size)}</span>
        </div>${collsHtml}`;
    }).join('');

    const navHtml = NAV_ITEMS.map(n => `
      <div class="nav-row ${cfg.activeNav === n.id ? 'is-active' : ''}">
        <span></span>
        <span class="nav-ico">${ICONS[n.icon]}</span>
        <span>${esc(n.label)}</span>
      </div>`).join('');

    return `
      <aside class="sidebar">
        <div class="brand">
          <span class="brand-mark" aria-hidden="true"></span>
          <span class="brand-word">Compass<span class="brand-plus">+</span></span>
          <span class="spacer"></span>
          <span class="dot is-success" title="Connected" style="margin-right:2px;"></span>
        </div>

        <div class="conn-switch" title="Switch connection">
          <span class="dot is-${esc(cfg.connection.status)}"></span>
          <span class="conn-meta">
            <div class="conn-name">${esc(cfg.connection.name)}</div>
            <div class="conn-host">${esc(cfg.connection.host)}</div>
          </span>
          <span class="chev">${ICONS.chevDown}</span>
        </div>

        <div class="search-field">
          <span class="ic">${ICONS.search}</span>
          <input placeholder="Search databases…" value="${esc(cfg.searchValue)}">
          <span class="mono" style="font-size:10px;color:var(--muted-2);">⌘K</span>
        </div>

        <div>
          <div class="section-head">Databases</div>
          <div class="db-tree">${dbsHtml}</div>
        </div>

        <div class="nav-list">
          <div class="section-head">Workspace</div>
          ${navHtml}
        </div>
      </aside>`;
  }

  function renderTabbar(tabs, activeIndex) {
    const list = (tabs || DEFAULT_TABS).map((t, i) => `
      <div class="tab ${i === activeIndex ? 'is-active' : ''}">
        <span class="db-dot" style="background:${t.dotColor || '#16A34A'};"></span>
        <span class="tab-name">${esc(t.db)}.${esc(t.coll)}</span>
        <span class="tab-close">${ICONS.close}</span>
      </div>`).join('');
    return `<div class="tabbar">${list}<button class="tab-add" title="New tab">${ICONS.plus}</button></div>`;
  }

  function renderStatusbar(s) {
    const cfg = Object.assign({
      connectionName: 'production-cluster',
      version: 'v7.0.5',
      latency: '12ms',
      ops: '1,284 ops/s',
    }, s || {});
    return `<div class="statusbar">
      <span><span class="dot is-success" style="margin-right:6px;"></span>${esc(cfg.connectionName)}</span>
      <span class="sep">•</span>
      <span class="mono">MongoDB ${esc(cfg.version)}</span>
      <span class="sep">•</span>
      <span class="latency">● ${esc(cfg.latency)}</span>
      <span class="spacer" style="flex:1;"></span>
      <span class="ops">${esc(cfg.ops)}</span>
    </div>`;
  }

  function renderWindow(opts) {
    const title = opts.title || 'Compass+ — production-cluster';
    const noShell = !!opts.noShell;
    const inner = noShell
      ? opts.body
      : `${renderSidebar(opts.sidebar)}
         <section class="main">
           ${renderTabbar(opts.tabs, opts.activeTab)}
           ${opts.body}
         </section>
         ${renderStatusbar(opts.statusbar)}`;

    return `<div class="mac-window">
      <header class="mac-titlebar">
        <span class="mac-traffic"><span class="tl-red"></span><span class="tl-yellow"></span><span class="tl-green"></span></span>
        <span class="mac-title">${esc(title)}</span>
        <span></span>
      </header>
      <div class="mac-body" ${noShell ? 'style="grid-template-columns:1fr;grid-template-rows:1fr;grid-template-areas:\'main\';"' : ''}>${inner}</div>
    </div>`;
  }

  window.Shell = { mount(opts) {
    const root = opts.root || document.body;
    root.insertAdjacentHTML('beforeend', renderWindow(opts));
  }, ICONS };
})();
