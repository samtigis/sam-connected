// =========================================================
// Sam Connected - Host Storage Server Web / Desktop GUI Logic
// =========================================================

const state = {
  activeTab: 'dashboard',
  currentConfig: null,
  mediaItems: [],
  devices: [],
  selectedDeviceId: '',
  activeFilter: 'all',
  searchQuery: '',
  lightboxIndex: -1,
  logLinesCount: 0,
};

function escapeHtml(str) {
  if (!str) return '';
  return String(str).replace(/[&<>"']/g, function(m) {
    return {
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&#39;'
    }[m];
  });
}

// Utilities
function formatBytes(bytes) {
  if (!bytes || bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let i = 0;
  let count = bytes;
  while (count >= 1024 && i < units.length - 1) {
    count /= 1024;
    i++;
  }
  return `${count.toFixed(1)} ${units[i]}`;
}

function showToast(message) {
  const container = document.getElementById('toastContainer');
  const toast = document.createElement('div');
  toast.className = 'toast';
  toast.textContent = message;
  container.appendChild(toast);
  setTimeout(() => {
    toast.style.opacity = '0';
    setTimeout(() => toast.remove(), 300);
  }, 3000);
}

// 1. Tab Navigation
function setupTabs() {
  const tabButtons = document.querySelectorAll('.tab-btn');
  tabButtons.forEach(btn => {
    btn.addEventListener('click', () => {
      const tabName = btn.dataset.tab;
      switchTab(tabName);
    });
  });
}

function switchTab(tabName) {
  state.activeTab = tabName;
  document.querySelectorAll('.tab-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.tab === tabName);
  });
  document.querySelectorAll('.tab-view').forEach(view => {
    view.classList.toggle('active', view.id === `view-${tabName}`);
  });

  if (tabName === 'gallery') {
    loadGallery();
  }
}

// 2. Fetch Server Config & Disk Metrics
async function fetchConfig() {
  try {
    const res = await fetch('/api/v1/system/config');
    if (!res.ok) return;
    const data = await res.json();
    state.currentConfig = data;

    // Update UI elements
    document.getElementById('apiUrlText').textContent = data.api_url;
    document.getElementById('storagePathDisplay').textContent = data.storage_path;

    // Disk Metrics
    if (data.disk) {
      const usedPct = data.disk.used_percent || 0;
      document.getElementById('diskUsagePercent').textContent = `${usedPct.toFixed(1)}%`;
      document.getElementById('diskProgressFill').style.width = `${Math.min(usedPct, 100)}%`;
      if (usedPct > 90) {
        document.getElementById('diskProgressFill').style.background = 'linear-gradient(90deg, #ef4444, #f87171)';
      }
      document.getElementById('diskUsedText').textContent = `Terpakai: ${formatBytes(data.disk.used_bytes)} (${usedPct.toFixed(1)}%)`;
      document.getElementById('diskFreeText').textContent = `Sisa Bebas: ${formatBytes(data.disk.free_bytes)}`;
    }

    // Media Counters
    if (data.stats) {
      document.getElementById('statPhotosCount').textContent = data.stats.total_images;
      document.getElementById('statVideosCount').textContent = data.stats.total_videos;
      document.getElementById('statTotalSize').textContent = formatBytes(data.stats.total_bytes);
      document.getElementById('badgeTotalMedia').textContent = data.stats.total_media;
    }
  } catch (err) {
    console.warn('Failed to load system config:', err);
  }
}

// 3. Folder Picker Dialog & File Explorer
function setupStorageActions() {
  // Ganti Folder Button
  document.getElementById('btnChangeStorageFolder').addEventListener('click', async () => {
    showToast('Membuka dialog pemilih folder Windows...');
    try {
      const res = await fetch('/api/v1/system/choose-folder', { method: 'POST' });
      const data = await res.json();
      if (data.selected && data.path) {
        // Save new folder
        const saveRes = await fetch('/api/v1/system/set-folder', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ path: data.path }),
        });
        if (saveRes.ok) {
          showToast(`Lokasi penyimpanan diubah: ${data.path}`);
          await fetchConfig();
        } else {
          showToast('Gagal mengubah lokasi penyimpanan.');
        }
      }
    } catch (err) {
      showToast('Gagal memproses pemilih folder: ' + err.message);
    }
  });

  // Open in File Explorer Buttons
  const openExplorer = async () => {
    try {
      await fetch('/api/v1/system/open-folder', { method: 'POST' });
      showToast('Membuka File Explorer...');
    } catch (err) {
      showToast('Gagal membuka File Explorer.');
    }
  };

  document.getElementById('btnOpenInExplorer').addEventListener('click', openExplorer);
  document.getElementById('btnOpenExplorerNav').addEventListener('click', openExplorer);

  // Copy API URL
  document.getElementById('btnCopyApiUrl').addEventListener('click', () => {
    const url = document.getElementById('apiUrlText').textContent;
    navigator.clipboard.writeText(url);
    showToast('Alamat API disalin ke clipboard');
  });

  // About Button
  document.getElementById('btnAbout').addEventListener('click', () => {
    alert("Sam Connected — Host Storage Server (Windows Edition)\nVersi: 1.0.0\n\nSolusi pencadangan foto & video lokal tanpa cloud publik.\nDikembangkan oleh Sam Tigis.");
  });
}

// 4. Live Server Logs Stream / Polling
async function pollLogs() {
  try {
    const res = await fetch('/api/v1/system/logs');
    if (!res.ok) return;
    const data = await res.json();
    const terminal = document.getElementById('logTerminal');

    if (data.logs && data.logs.length > 0) {
      terminal.innerHTML = '';
      data.logs.forEach(entry => {
        const line = document.createElement('div');
        line.className = 'log-line';

        const msg = entry.message;
        if (msg.includes('[INIT]') || msg.includes('[SERVER]')) {
          line.classList.add('info');
        } else if (msg.includes('200') || msg.includes('[DB]') || msg.includes('success')) {
          line.classList.add('success');
        } else if (msg.includes('[WARN]') || msg.includes('404')) {
          line.classList.add('warn');
        } else if (msg.includes('[FATAL]') || msg.includes('500') || msg.includes('error')) {
          line.classList.add('error');
        }

        line.textContent = `[${entry.timestamp || entry.Timestamp}] ${msg}`;
        terminal.appendChild(line);
      });

      const autoScroll = document.getElementById('chkAutoScroll').checked;
      if (autoScroll) {
        terminal.scrollTop = terminal.scrollHeight;
      }
    }
  } catch (err) {
    // Ignore polling errors
  }
}

document.getElementById('btnClearLogs').addEventListener('click', async () => {
  await fetch('/api/v1/system/clear-logs', { method: 'POST' });
  document.getElementById('logTerminal').innerHTML = '<div class="log-line info">[SISTEM] Log dibersihkan.</div>';
  showToast('Log dibersihkan');
});

// 5. Connected Devices Detection & Management
async function fetchDevices() {
  try {
    const res = await fetch('/api/v1/devices');
    if (!res.ok) return;
    const data = await res.json();
    state.devices = data.devices || [];

    const badge = document.getElementById('badgeDeviceCount');
    if (badge) {
      badge.textContent = `${state.devices.length} Perangkat`;
    }

    // Populate dashboard devices list
    const container = document.getElementById('devicesListContainer');
    if (container) {
      if (state.devices.length === 0) {
        container.innerHTML = `
          <div style="font-size: 13px; color: var(--text-muted); text-align: center; padding: 12px;">
            Belum ada perangkat klien yang terhubung atau melakukan backup.
          </div>`;
      } else {
        container.innerHTML = '';
        state.devices.forEach(dev => {
          const item = document.createElement('div');
          item.style.cssText = 'display: flex; align-items: center; justify-content: space-between; padding: 10px 14px; background: var(--bg-card); border: 1px solid var(--border); border-radius: 8px; font-size: 13px;';
          
          const lastActiveStr = dev.last_active ? new Date(dev.last_active).toLocaleString('id-ID', { dateStyle: 'short', timeStyle: 'short' }) : '-';

          const displayName = dev.display_name || dev.custom_name || dev.device_id;
          const hasCustomName = Boolean(dev.custom_name);

          item.innerHTML = `
            <div style="display: flex; align-items: center; gap: 10px;">
              <div style="width: 32px; height: 32px; border-radius: 8px; background: rgba(59, 130, 246, 0.1); color: #3b82f6; display: flex; align-items: center; justify-content: center;">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                  <rect x="5" y="2" width="14" height="20" rx="2" ry="2"></rect>
                  <line x1="12" y1="18" x2="12.01" y2="18"></line>
                </svg>
              </div>
              <div>
                <div style="font-weight: 600; color: var(--text);">${escapeHtml(displayName)}</div>
                <div style="font-size: 11px; color: var(--text-muted);">${hasCustomName ? `ID: ${escapeHtml(dev.device_id)} • ` : ''}${dev.total_media} media (${formatBytes(dev.total_bytes)}) • Aktif: ${lastActiveStr}</div>
              </div>
            </div>
            <div style="display: flex; align-items: center; gap: 6px;">
              <button class="btn btn-sm btn-outline btn-rename-device" data-device="${escapeHtml(dev.device_id)}" style="padding: 4px 8px; font-size: 12px; display: inline-flex; align-items: center; gap: 4px;" title="Beri nama custom perangkat ini">
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"></path><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"></path></svg>
                Beri Nama
              </button>
              <button class="btn btn-sm btn-outline btn-view-device-gallery" data-device="${escapeHtml(dev.device_id)}" style="padding: 4px 10px; font-size: 12px;">
                Lihat Galeri
              </button>
            </div>
          `;

          const renameBtn = item.querySelector('.btn-rename-device');
          renameBtn.addEventListener('click', async () => {
            const currentName = dev.custom_name || dev.display_name || '';
            const newName = prompt(`Beri nama untuk perangkat "${dev.device_id}":\n(Nama ini otomatis muncul di seluruh HP/iPad klien)`, currentName);
            if (newName !== null) {
              try {
                const res = await fetch(`/api/v1/devices/${encodeURIComponent(dev.device_id)}/name`, {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json' },
                  body: JSON.stringify({ name: newName.trim() }),
                });
                if (res.ok) {
                  showToast(`Nama perangkat "${dev.device_id}" berhasil disimpan!`);
                  await fetchDevices();
                } else {
                  showToast('Gagal mengubah nama perangkat.');
                }
              } catch (e) {
                showToast('Error: ' + e.message);
              }
            }
          });

          const viewBtn = item.querySelector('.btn-view-device-gallery');
          viewBtn.addEventListener('click', () => {
            state.selectedDeviceId = dev.device_id;
            const select = document.getElementById('galleryDeviceSelect');
            if (select) select.value = dev.device_id;
            switchTab('gallery');
          });

          container.appendChild(item);
        });
      }
    }

    // Populate gallery device dropdown
    const select = document.getElementById('galleryDeviceSelect');
    if (select) {
      const currentVal = state.selectedDeviceId;
      select.innerHTML = '<option value="">Semua Perangkat</option>';
      state.devices.forEach(dev => {
        const opt = document.createElement('option');
        opt.value = dev.device_id;
        const label = dev.display_name || dev.custom_name || dev.device_id;
        opt.textContent = `${label} (${dev.total_media} media)`;
        if (dev.device_id === currentVal) {
          opt.selected = true;
        }
        select.appendChild(opt);
      });
    }
  } catch (err) {
    console.warn('Gagal memuat perangkat:', err);
  }
}

// 5. Gallery Management (Google Photos Style)
async function loadGallery() {
  const grid = document.getElementById('galleryGrid');
  const emptyState = document.getElementById('galleryEmptyState');

  let url = `/api/v1/media?limit=100`;
  if (state.activeFilter === 'image' || state.activeFilter === 'video') {
    url += `&type=${state.activeFilter}`;
  } else if (state.activeFilter === 'favorite') {
    url += `&favorite=true`;
  }
  if (state.selectedDeviceId) {
    url += `&device_id=${encodeURIComponent(state.selectedDeviceId)}`;
  }
  if (state.searchQuery) {
    url += `&search=${encodeURIComponent(state.searchQuery)}`;
  }

  try {
    const res = await fetch(url);
    if (!res.ok) return;
    const data = await res.json();
    state.mediaItems = data.data || data.items || [];

    grid.innerHTML = '';

    if (state.mediaItems.length === 0) {
      grid.style.display = 'none';
      emptyState.style.display = 'block';
      return;
    }

    grid.style.display = 'grid';
    emptyState.style.display = 'none';

    state.mediaItems.forEach((item, index) => {
      const card = document.createElement('div');
      card.className = 'media-card';
      card.dataset.index = index;

      const isVideo = item.mime_type && item.mime_type.startsWith('video/');
      const isHeic = (item.file_name && /\.(heic|heif)$/i.test(item.file_name)) ||
                     (item.extension && /\.(heic|heif)$/i.test(item.extension));
      const thumbUrl = `/api/v1/media/${item.id}/thumb`;

      let durationBadge = '▶ Video';
      if (isVideo && item.duration > 0) {
        const m = Math.floor(item.duration / 60);
        const s = Math.floor(item.duration % 60);
        durationBadge = `▶ ${m}:${String(s).padStart(2, '0')}`;
      }

      card.innerHTML = `
        <img class="media-thumb" src="${thumbUrl}" loading="lazy" alt="${escapeHtml(item.file_name)}" onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';">
        <div class="media-fallback ${isVideo ? 'video-fallback' : 'image-fallback'}" style="display: none;">
          <div class="fallback-icon">
            ${isVideo 
              ? '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polygon points="23 7 16 12 23 17 23 7"></polygon><rect x="1" y="5" width="15" height="14" rx="2" ry="2"></rect></svg>' 
              : '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="2" ry="2"></rect><circle cx="8.5" cy="8.5" r="1.5"></circle><polyline points="21 15 16 10 5 21"></polyline></svg>'}
          </div>
          <div class="fallback-name">${escapeHtml(item.file_name)}</div>
        </div>
        ${isVideo ? `<div class="media-badge video">${durationBadge}</div>` : ''}
        ${isHeic ? `<div class="media-badge" style="position: absolute; top: 6px; left: 6px; background: rgba(14, 165, 233, 0.85); color: white; padding: 2px 6px; border-radius: 4px; font-size: 10px; font-weight: 600;">HEIC</div>` : ''}
        ${item.is_favorite ? `<div class="media-badge fav"><svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor" stroke="currentColor" stroke-width="1"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"></polygon></svg></div>` : ''}
        <div class="media-overlay">
          <div>${escapeHtml(item.file_name)}</div>
          <div>${formatBytes(item.file_size)}</div>
        </div>
      `;

      card.addEventListener('click', () => openLightbox(index));
      grid.appendChild(card);
    });
  } catch (err) {
    console.warn('Gagal memuat galeri:', err);
  }
}

// Gallery Filters & Search
function setupGalleryControls() {
  document.querySelectorAll('.filter-pill').forEach(pill => {
    pill.addEventListener('click', () => {
      document.querySelectorAll('.filter-pill').forEach(p => p.classList.remove('active'));
      pill.classList.add('active');
      state.activeFilter = pill.dataset.filter;
      loadGallery();
    });
  });

  const searchInput = document.getElementById('gallerySearchInput');
  let searchTimer;
  searchInput.addEventListener('input', (e) => {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => {
      state.searchQuery = e.target.value.trim();
      loadGallery();
    }, 300);
  });

  const deviceSelect = document.getElementById('galleryDeviceSelect');
  if (deviceSelect) {
    deviceSelect.addEventListener('change', (e) => {
      state.selectedDeviceId = e.target.value;
      loadGallery();
    });
  }

  document.getElementById('btnRefreshGallery').addEventListener('click', () => {
    loadGallery();
    showToast('Galeri dimuat ulang');
  });
}

// 6. Interactive Lightbox Viewer
function openLightbox(index) {
  if (index < 0 || index >= state.mediaItems.length) return;
  state.lightboxIndex = index;
  const item = state.mediaItems[index];

  const modal = document.getElementById('lightboxModal');
  const mediaContainer = document.getElementById('lightboxMediaContainer');
  const isVideo = item.mime_type && item.mime_type.startsWith('video/');
  const isHeic = (item.file_name && /\.(heic|heif)$/i.test(item.file_name)) ||
                 (item.extension && /\.(heic|heif)$/i.test(item.extension)) ||
                 (item.mime_type && /heic|heif/i.test(item.mime_type));
  const rawUrl = `/api/v1/media/${item.id}/raw/${encodeURIComponent(item.file_name || 'media')}`;
  const thumbUrl = `/api/v1/media/${item.id}/thumb`;

  document.getElementById('lightboxFileName').textContent = item.file_name;
  document.getElementById('metaTakenAt').textContent = item.taken_at ? new Date(item.taken_at).toLocaleString('id-ID') : '-';
  document.getElementById('metaDevice').textContent = item.device_id || 'Unknown';

  const durSec = item.duration || 0;
  if (durSec > 0) {
    const mins = Math.floor(durSec / 60);
    const secs = Math.floor(durSec % 60);
    document.getElementById('metaResolution').textContent = `${(item.width && item.height) ? `${item.width} × ${item.height} px • ` : ''}Durasi: ${mins}:${String(secs).padStart(2, '0')}`;
  } else {
    document.getElementById('metaResolution').textContent = (item.width && item.height) ? `${item.width} × ${item.height} px` : '-';
  }

  document.getElementById('metaSize').textContent = formatBytes(item.file_size);
  document.getElementById('metaHash').textContent = item.hash || '-';

  // Download & Favorite buttons
  const dlBtn = document.getElementById('btnLightboxDownload');
  dlBtn.href = rawUrl;
  dlBtn.download = item.file_name;

  const favBtn = document.getElementById('btnLightboxFavorite');
  favBtn.innerHTML = item.is_favorite 
    ? '<svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" stroke="currentColor" stroke-width="1"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"></polygon></svg>'
    : '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"></polygon></svg>';
  favBtn.onclick = async () => {
    await fetch(`/api/v1/media/${item.id}/favorite`, { method: 'POST' });
    item.is_favorite = !item.is_favorite;
    favBtn.innerHTML = item.is_favorite 
      ? '<svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" stroke="currentColor" stroke-width="1"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"></polygon></svg>'
      : '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"></polygon></svg>';
    loadGallery();
  };

  // Delete button
  const delBtn = document.getElementById('btnLightboxDelete');
  delBtn.onclick = async () => {
    if (confirm(`Yakin ingin menghapus berkas "${item.file_name}" dari server?`)) {
      await fetch(`/api/v1/media/${item.id}`, { method: 'DELETE' });
      showToast('Media dihapus dari server');
      closeLightbox();
      loadGallery();
      fetchConfig();
    }
  };

  if (isVideo) {
    mediaContainer.innerHTML = `
      <div style="display: flex; flex-direction: column; align-items: center; max-height: 100%; max-width: 100%;">
        <video src="${rawUrl}" controls autoplay style="max-height: 75vh; max-width: 100%; border-radius: 8px; box-shadow: 0 10px 30px rgba(0,0,0,0.5);"></video>
        <div style="display: flex; align-items: center; justify-content: center; gap: 10px; margin-top: 10px; flex-wrap: wrap;">
          <button id="btnOpenInSystemPlayer" class="btn btn-sm btn-primary" style="padding: 6px 14px; font-size: 12px; display: inline-flex; align-items: center; gap: 6px;">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polygon points="5 3 19 12 5 21 5 3"></polygon></svg>
            Buka di Player Windows (VLC / Media Player)
          </button>
          <a href="${rawUrl}" download="${escapeHtml(item.file_name)}" class="btn btn-sm btn-outline" style="padding: 6px 12px; font-size: 12px; display: inline-flex; align-items: center; gap: 6px;">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path><polyline points="7 10 12 15 17 10"></polyline><line x1="12" y1="15" x2="12" y2="3"></line></svg>
            Unduh File Asli
          </a>
        </div>
        <div style="font-size: 11px; color: var(--text-muted); margin-top: 6px; text-align: center; display: inline-flex; align-items: center; gap: 4px;">
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"></circle><line x1="12" y1="16" x2="12" y2="12"></line><line x1="12" y1="8" x2="12.01" y2="8"></line></svg>
          Tip: Video format Apple (HEVC/QuickTime). Jika layar hitam di browser Windows, klik tombol "Buka di Player Windows" di atas untuk memutar langsung dengan akselerasi penuh.
        </div>
      </div>
    `;

    const openSysBtn = document.getElementById('btnOpenInSystemPlayer');
    if (openSysBtn) {
      openSysBtn.addEventListener('click', async () => {
        try {
          const res = await fetch('/api/v1/system/open-file', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ media_id: item.id }),
          });
          if (res.ok) {
            showToast('Membuka video di pemutar Windows...');
          } else {
            showToast('Gagal membuka di pemutar Windows.');
          }
        } catch (e) {
          showToast('Error: ' + e.message);
        }
      });
    }
  } else if (isHeic) {
    mediaContainer.innerHTML = `
      <div style="display: flex; flex-direction: column; align-items: center; max-height: 100%; max-width: 100%;">
        <img src="${thumbUrl}" alt="${escapeHtml(item.file_name)}" style="max-height: 75vh; max-width: 100%; object-fit: contain; border-radius: 8px; box-shadow: 0 10px 30px rgba(0,0,0,0.4);">
        <div style="display: flex; align-items: center; justify-content: center; gap: 10px; margin-top: 10px; flex-wrap: wrap;">
          <button id="btnOpenInSystemPhoto" class="btn btn-sm btn-primary" style="padding: 6px 14px; font-size: 12px; display: inline-flex; align-items: center; gap: 6px;">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="2" ry="2"></rect><circle cx="8.5" cy="8.5" r="1.5"></circle><polyline points="21 15 16 10 5 21"></polyline></svg>
            Buka di Aplikasi Photos Windows
          </button>
          <a href="${rawUrl}" download="${escapeHtml(item.file_name)}" class="btn btn-sm btn-outline" style="padding: 6px 12px; font-size: 12px; display: inline-flex; align-items: center; gap: 6px;">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path><polyline points="7 10 12 15 17 10"></polyline><line x1="12" y1="15" x2="12" y2="3"></line></svg>
            Unduh File Asli (.HEIC)
          </a>
        </div>
        <div style="font-size: 11px; color: #38bdf8; margin-top: 6px; text-align: center; background: rgba(56, 189, 248, 0.1); padding: 4px 12px; border-radius: 6px; display: inline-flex; align-items: center; gap: 6px;">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"></path><circle cx="12" cy="13" r="4"></circle></svg>
          Format Apple HEIC (Pratinjau JPEG Kualitas Tinggi) • Klik "Buka di Aplikasi Photos" untuk melihat file asli.
        </div>
      </div>
    `;

    const openPhotoBtn = document.getElementById('btnOpenInSystemPhoto');
    if (openPhotoBtn) {
      openPhotoBtn.addEventListener('click', async () => {
        try {
          const res = await fetch('/api/v1/system/open-file', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ media_id: item.id }),
          });
          if (res.ok) {
            showToast('Membuka foto di aplikasi Windows Photos...');
          } else {
            showToast('Gagal membuka foto di Windows.');
          }
        } catch (e) {
          showToast('Error: ' + e.message);
        }
      });
    }
  } else {
    mediaContainer.innerHTML = `
      <div style="display: flex; flex-direction: column; align-items: center; max-height: 100%; max-width: 100%;">
        <img src="${rawUrl}" alt="${escapeHtml(item.file_name)}" style="max-height: 80vh; max-width: 100%; object-fit: contain; border-radius: 8px;" onerror="this.onerror=null; this.src='${thumbUrl}';">
        <div style="margin-top: 8px;">
          <button id="btnOpenInSystemPhoto" class="btn btn-sm btn-outline" style="padding: 4px 12px; font-size: 12px; display: inline-flex; align-items: center; gap: 6px;">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="2" ry="2"></rect><circle cx="8.5" cy="8.5" r="1.5"></circle><polyline points="21 15 16 10 5 21"></polyline></svg>
            Buka di Aplikasi Windows
          </button>
        </div>
      </div>
    `;

    const openPhotoBtn = document.getElementById('btnOpenInSystemPhoto');
    if (openPhotoBtn) {
      openPhotoBtn.addEventListener('click', async () => {
        try {
          await fetch('/api/v1/system/open-file', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ media_id: item.id }),
          });
          showToast('Membuka foto di Windows...');
        } catch (_) {}
      });
    }
  }

  modal.classList.add('active');
}

function closeLightbox() {
  const modal = document.getElementById('lightboxModal');
  modal.classList.remove('active');
  document.getElementById('lightboxMediaContainer').innerHTML = '';
  state.lightboxIndex = -1;
}

function setupLightboxControls() {
  document.getElementById('btnLightboxClose').addEventListener('click', closeLightbox);
  document.getElementById('lightboxBackdrop').addEventListener('click', closeLightbox);

  document.getElementById('btnLightboxPrev').addEventListener('click', () => {
    if (state.lightboxIndex > 0) {
      openLightbox(state.lightboxIndex - 1);
    }
  });

  document.getElementById('btnLightboxNext').addEventListener('click', () => {
    if (state.lightboxIndex < state.mediaItems.length - 1) {
      openLightbox(state.lightboxIndex + 1);
    }
  });

  window.addEventListener('keydown', (e) => {
    const modal = document.getElementById('lightboxModal');
    if (!modal.classList.contains('active')) return;

    if (e.key === 'Escape') closeLightbox();
    if (e.key === 'ArrowLeft' && state.lightboxIndex > 0) {
      openLightbox(state.lightboxIndex - 1);
    }
    if (e.key === 'ArrowRight' && state.lightboxIndex < state.mediaItems.length - 1) {
      openLightbox(state.lightboxIndex + 1);
    }
  });
}

// Initialize Application
document.addEventListener('DOMContentLoaded', () => {
  setupTabs();
  setupStorageActions();
  setupGalleryControls();
  setupLightboxControls();

  fetchConfig();
  fetchDevices();
  pollLogs();

  // Periodic Refresh
  setInterval(fetchConfig, 5000);
  setInterval(fetchDevices, 6000);
  setInterval(pollLogs, 2500);
});
