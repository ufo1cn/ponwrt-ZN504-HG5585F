'use strict';
'require view';
'require rpc';
'require ui';
'require poll';

var callStatus = rpc.declare({ object: 'luci.ponwrt_update', method: 'status' });
var callCheck = rpc.declare({ object: 'luci.ponwrt_update', method: 'check' });
var callDetect = rpc.declare({ object: 'luci.ponwrt_update', method: 'detect' });
var callSet = rpc.declare({ object: 'luci.ponwrt_update', method: 'set', params: [ 'mode', 'proxy', 'index_base' ] });
var callDownload = rpc.declare({ object: 'luci.ponwrt_update', method: 'download', params: [ 'url', 'sha256' ] });
var callApply = rpc.declare({ object: 'luci.ponwrt_update', method: 'apply', params: [ 'wipe' ] });

var MODES = [
	[ 'direct', '直连（不使用代理）' ],
	[ 'proxy', '使用代理（HTTP / SOCKS 端口）' ],
	[ 'transparent', '透明代理（TUN / nftables redir 已生效）' ]
];

function fmtSize(n) {
	n = parseInt(n, 10) || 0;
	if (n >= 1048576)
		return (n / 1048576).toFixed(1) + ' MiB';
	if (n >= 1024)
		return (n / 1024).toFixed(0) + ' KiB';
	return n + ' B';
}

function kv(label, value) {
	var field = E('div', { 'class': 'cbi-value-field' });

	if (value == null || value === '')
		field.textContent = '—';
	else if (typeof value === 'object' && value.nodeType)
		field.appendChild(value);          // 控件（select/input/button…）要挂节点，不能 String()
	else
		field.textContent = String(value);

	return E('div', { 'class': 'cbi-value' }, [
		E('label', { 'class': 'cbi-value-title' }, label),
		field
	]);
}

return view.extend({
	load: function() {
		return callStatus();
	},

	updateProgress: function(st) {
		var bar = document.getElementById('pu-bar');
		var txt = document.getElementById('pu-progress-text');
		var applyBtn = document.getElementById('pu-apply');
		if (!bar || !txt || !applyBtn)
			return;

		var total = parseInt(st.total, 10) || 0;
		var done = parseInt(st.bytes, 10) || 0;
		var pct = total > 0 ? Math.min(100, Math.floor(done * 100 / total)) : 0;

		switch (st.state) {
		case 'downloading':
			bar.style.width = pct + '%';
			txt.textContent = '下载中：' + fmtSize(done) + ' / ' + (total ? fmtSize(total) : '未知') + '（' + pct + '%）';
			applyBtn.disabled = true;
			break;
		case 'ready':
			bar.style.width = '100%';
			txt.textContent = '已下载并通过 sha256 校验：' + (st.filename || '') + '（' + fmtSize(total) + '）';
			applyBtn.disabled = false;
			break;
		case 'error':
		case 'sha_mismatch':
			bar.style.width = pct + '%';
			txt.textContent = '下载出错：' + (st.error || st.state);
			applyBtn.disabled = true;
			break;
		default:
			bar.style.width = '0%';
			txt.textContent = '尚未下载镜像';
			applyBtn.disabled = true;
		}
	},

	render: function(st) {
		var self = this;
		var remote = null;

		var modeSel = E('select', { 'class': 'cbi-input-select', 'style': 'min-width:22em' },
			MODES.map(function(m) {
				var o = E('option', { 'value': m[0] }, m[1]);
				if ((st.mode || 'direct') === m[0])
					o.selected = true;
				return o;
			}));

		var proxyInput = E('input', {
			'type': 'text',
			'class': 'cbi-input-text',
			'placeholder': 'http://127.0.0.1:7890 或 socks5h://127.0.0.1:7891',
			'value': st.proxy || ''
		});

		var idxInput = E('input', {
			'type': 'text',
			'class': 'cbi-input-text',
			'placeholder': 'https://raw.githubusercontent.com/ufo1cn/ponwrt-apk-repo/repo/meta/fw',
			'value': st.index_base || ''
		});

		var hitsBox = E('div', { 'class': 'cbi-value-description', 'style': 'margin-top:.4em' });

		var detectBtn = E('button', {
			'class': 'cbi-button cbi-button-neutral',
			'click': function() {
				hitsBox.innerHTML = '';
				hitsBox.textContent = '正在读取本机代理配置…';
				callDetect().then(function(r) {
					hitsBox.innerHTML = '';
					var items = (r && r.items) || [];
					if (!items.length) {
						hitsBox.textContent = '没在 mihomo / sing-box / xray 的配置里找到监听端口，请直接手填';
						return;
					}
					hitsBox.appendChild(E('span', {}, '探测到：'));
					items.forEach(function(it) {
						var parts = String(it).split(':');
						var port = parts.pop();
						var label = parts.join(':');
						if (!port)
							return;
						hitsBox.appendChild(E('button', {
							'class': 'cbi-button cbi-button-neutral',
							'style': 'margin:0 .4em .4em 0',
							'click': function() {
								proxyInput.value = 'http://127.0.0.1:' + port;
							}
						}, label + ' → http://127.0.0.1:' + port));
					});
					hitsBox.appendChild(E('p', { 'class': 'cbi-value-description' },
						'点一下就把该端口填进"代理地址"，然后记得保存。混合端口同时吃 HTTP 和 SOCKS，最省事。'));
				});
			}
		}, '探测本机正在跑的代理');

		var resultBox = E('div', { 'id': 'pu-result', 'style': 'margin-top:.5em' });
		var bar = E('div', { 'id': 'pu-bar', 'style': 'height:100%;width:0%;background:var(--primary-color-high,#1565c0);transition:width .3s' });
		var progressText = E('div', { 'id': 'pu-progress-text', 'class': 'cbi-value-description' }, '尚未下载镜像');

		var wipeCheck = E('input', { 'type': 'checkbox', 'id': 'pu-wipe' });

		var applyBtn = E('button', {
			'id': 'pu-apply',
			'class': 'cbi-button cbi-button-action',
			'disabled': true,
			'click': function() {
				ui.showModal('确认刷写固件', [
					E('p', {}, '将使用 /tmp 里已通过 sha256 校验的镜像调用 sysupgrade 刷写，设备会自动重启，请勿断电。'),
					E('div', { 'class': 'right' }, [
						E('button', {
							'class': 'cbi-button cbi-button-neutral',
							'click': function() { ui.hideModal(); }
						}, '取消'),
						E('button', {
							'class': 'cbi-button cbi-button-negative',
							'click': function() {
								ui.hideModal();
								applyBtn.disabled = true;
								callApply(document.getElementById('pu-wipe').checked ? '1' : '0').then(function(r) {
									progressText.textContent = r && r.ok ? (r.message || '已开始刷写') : '刷写失败：' + (r.error || '未知错误');
								});
							}
						}, '开始刷写')
					])
				]);
			}
		}, '刷写已下载的镜像');

		var downloadBtn = E('button', {
			'class': 'cbi-button cbi-button-apply',
			'disabled': true,
			'click': function() {
				if (!remote || !remote.url)
					return;
				downloadBtn.disabled = true;
				callDownload(remote.url, remote.sha256 || '').then(function(r) {
					if (r && r.ok)
						progressText.textContent = r.message || '已开始下载';
					else
						progressText.textContent = '下载失败：' + (r && r.error || '未知错误');
				});
			}
		}, '下载新固件');

		var checkBtn = E('button', {
			'class': 'cbi-button cbi-button-action',
			'click': function() {
				checkBtn.disabled = true;
				resultBox.innerHTML = '';
				resultBox.appendChild(E('p', { 'class': 'cbi-value-description' }, '正在拉取索引…'));
				callCheck().then(function(r) {
					checkBtn.disabled = false;
					resultBox.innerHTML = '';
					if (!r || !r.ok) {
						resultBox.appendChild(E('p', { 'class': 'cbi-value-description' },
							'检查失败：' + (r && r.error || '未知错误')));
						if (r && r.hint)
							resultBox.appendChild(E('p', { 'class': 'cbi-value-description' }, r.hint));
						return;
					}
					if (r.update) {
						remote = r;
						resultBox.appendChild(E('p', {}, [
							E('strong', {}, '发现新固件：'),
							' ' + (r.tag || '') + '（仓库 run ' + r.remote_run + '，本地 run ' + r.local_run + '）'
						]));
						resultBox.appendChild(E('p', {}, '镜像：' + (r.name || '—')));
						resultBox.appendChild(E('p', {}, 'sha256：' + (r.sha256 || '—')));
						resultBox.appendChild(E('p', {}, '远端构建：' + (r.remote_built_at || '—') +
							'（本地 ' + (st.built_at || '—') + '）'));
						resultBox.appendChild(E('p', {}, '地址：' + (r.url || '—')));
						downloadBtn.disabled = false;
					}
					else {
						remote = null;
						resultBox.appendChild(E('p', {}, '已是最新固件（仓库 tag ' + (r.tag || '') + '，run ' + r.remote_run +
								'，构建 ' + (r.remote_built_at || '—') + '）'));
						downloadBtn.disabled = true;
					}
				});
			}
		}, '检查更新');

		var saveBtn = E('button', {
			'class': 'cbi-button cbi-button-save',
			'click': function() {
				saveBtn.disabled = true;
				callSet(modeSel.value, proxyInput.value, idxInput.value).then(function(r) {
					saveBtn.disabled = false;
					if (r && r.ok) {
						ui.addNotification(null, E('p', {}, '更新设置已保存（立即生效，无需重启）'), 'info');
						proxyInput.value = r.proxy || '';
						idxInput.value = r.index_base || '';
					} else {
						ui.addNotification(null, E('p', {}, '保存失败：' + (r && r.error || '未知错误')), 'error');
					}
				});
			}
		}, '保存设置');

		poll.add(function() {
			return callStatus().then(function(s) {
				self.updateProgress(s);
			});
		}, 3);

		self.updateProgress(st);

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, '固件更新'),
			E('p', { 'class': 'cbi-map-descr' }, [
				E('strong', {}, '当前固件：'),
				(st.device || '未知') + ' · ' + (st.feature_class || '—') +
				' · run ' + (st.local_run || '?') + ' · commit ' + (st.commit || '?') +
				' · 构建 ' + (st.built_at || '未知')
			]),
			E('div', { 'class': 'cbi-map-descr' },
				'从自建 apk 仓库的 meta/fw 索引检查是否有新固件，下载后按索引里的 sha256 校验再刷写。' +
				'索引只包含本机机型（' + (st.device || '未知') + '）对应的那一份。'),
			E('fieldset', { 'class': 'cbi-section' }, [
				E('h3', {}, '更新设置'),
				kv('出站方式', modeSel),
				kv('代理地址', proxyInput),
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, '本机代理'),
					E('div', { 'class': 'cbi-value-field' }, [ detectBtn, hitsBox ])
				]),
				kv('仓库索引地址', idxInput),
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, ''),
					E('div', { 'class': 'cbi-value-field' }, saveBtn)
				]),
				E('p', { 'class': 'cbi-value-description' },
					'直连 = 完全不使用代理（显式绕过系统里的 http_proxy）；使用代理 = 只对本次检查/下载显式走该端口，' +
					'可直接指向本机正在跑的 mihomo / sing-box / xray（用上面的"探测"按钮或手填 http://127.0.0.1:7890）；' +
					'透明代理 = 这些工具的 TUN 或 nftables redir 已经接管全部出站，这里不再传代理参数。' +
					'索引地址可改成你自己的镜像（目录形式，实际取 <地址>/<机型>.json）。')
			]),
			E('fieldset', { 'class': 'cbi-section' }, [
				E('h3', {}, '本机版本'),
				kv('机型', st.device),
				kv('能力类别', st.feature_class),
				kv('源码 commit', st.commit),
				kv('构建时间（UTC）', st.built_at),
				kv('固件 run', st.local_run),
				kv('内核', st.kernel),
				kv('索引地址', st.index_base)
			]),
			E('fieldset', { 'class': 'cbi-section' }, [
				E('h3', {}, '检查与下载'),
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, ''),
					E('div', { 'class': 'cbi-value-field' }, [ checkBtn, ' ', downloadBtn ])
				]),
				resultBox,
				E('div', { 'style': 'margin:1em 0 .5em' }, [
					E('div', { 'style': 'background:var(--border-color-medium,#d0d7de);border-radius:4px;overflow:hidden;height:6px' }, [ bar ]),
					progressText
				])
			]),
			E('fieldset', { 'class': 'cbi-section' }, [
				E('h3', {}, '刷写'),
				kv('不保留配置', wipeCheck),
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, ''),
					E('div', { 'class': 'cbi-value-field' }, applyBtn)
				]),
				E('p', { 'class': 'cbi-value-description' },
					'默认保留当前配置（sysupgrade 常规行为）；勾选"不保留配置"相当于 sysupgrade -n，恢复出厂。' +
					'刷写只使用 /tmp 里通过校验的镜像，不会去网上边下边刷。')
			])
		]);
	}
});
