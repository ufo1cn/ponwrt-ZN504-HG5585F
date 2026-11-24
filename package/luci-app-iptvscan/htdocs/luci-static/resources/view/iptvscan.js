'use strict';
'require view';
'require form';
'require uci';
'require fs';
'require ui';

function parseKv(text) {
	var out = {};

	(text || '').split('\n').forEach(function(line) {
		var i = line.indexOf('=');

		if (i > 0)
			out[line.slice(0, i)] = line.slice(i + 1);
	});

	return out;
}

function esc(s) {
	return String(s == null ? '' : s)
		.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;');
}

function rowByTitle(title) {
	var found = null;

	document.querySelectorAll('.cbi-value').forEach(function(row) {
		var t = row.querySelector('.cbi-value-title');

		if (!found && t && t.textContent.trim() === title)
			found = row;
	});

	return found;
}

function toggleRows(titles, show) {
	titles.forEach(function(title) {
		var row = rowByTitle(title);

		if (row)
			row.style.display = show ? '' : 'none';
	});
}

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('iptvscan').catch(function() { return null; }),
			uci.load('rtp2httpd').catch(function() { return null; }),
			fs.read('/tmp/iptvscan.status').catch(function() { return ''; }),
			fs.read('/etc/iptvscan-groups.db').catch(function() { return ''; }),
			fs.read('/proc/net/dev').catch(function() { return ''; }),
			fs.read('/tmp/iptvscan.cred').catch(function() { return ''; })
		]);
	},

	render: function(data) {
		var st = parseKv(data[2]);
		var db = (data[3] || '').split('\n').filter(function(l) { return l.indexOf('239.') === 0; });
		var cred = parseKv(data[5]);
		var nics = (data[4] || '').split('\n').map(function(l) {
			return l.split(':')[0].trim();
		}).filter(function(n) {
			return n && n !== 'Inter-|' && n !== ' face';
		});

		var listenRaw = uci.get('rtp2httpd', 'main', 'listen');
		var listen = Array.isArray(listenRaw) ? listenRaw[0] : listenRaw;
		var port = '4022';

		if (typeof(listen) === 'string' && listen.length)
			port = listen.split(':').pop();

		var playUrl = 'http://%s:%s/playlist.m3u'.format(window.location.hostname, port);

		var statusText, statusColor;

		if (st.state === 'running')      { statusText = _('抓包中'); statusColor = '#f0a020'; }
		else if (st.state === 'done')    { statusText = _('已完成'); statusColor = '#3c9d3c'; }
		else if (st.state === 'failed')  { statusText = _('失败');   statusColor = '#d03030'; }
		else                             { statusText = _('空闲');   statusColor = '#888'; }

		var statusHtml = '<span style="color:%s;font-weight:bold">%s</span>'.format(statusColor, statusText);

		if (st.msg)
			statusHtml += ' &nbsp;<span class="cbi-value-description">%s</span>'.format(esc(st.msg));

		var tableHtml = '<div style="max-height:22em;overflow:auto"><table class="cbi-section-table" style="width:100%">' +
			'<tr><th>' + _('组播地址') + '</th><th>' + _('端口') + '</th><th>' + _('名称') + '</th></tr>';

		if (db.length === 0)
			tableHtml += '<tr><td colspan="3">' + _('还没有频道，点下面的「立即扫描」') + '</td></tr>';
		else
			db.forEach(function(line) {
				var f = line.trim().split(/\s+/);
				tableHtml += '<tr><td>%s</td><td>%s</td><td>%s</td></tr>'
					.format(esc(f[0]), esc(f[1] || '-'), esc(f[2] || ''));
			});

		tableHtml += '</table></div>';

		var m = new form.Map('iptvscan', _('IPTV 组播接入与频道扫描'),
			_('两种线路形态二选一：组播 VLAN 上能收到裸组播就走 mvlan；组播锁在机顶盒 PPPoE 会话里就让路由器接管拨号走 pppoe。选 auto 会先探测再决定。'));

		var s = m.section(form.NamedSection, 'main', 'iptvscan', _('线路与扫描设置'));
		s.anonymous = true;

		var o = s.option(form.Select, 'mode', _('线路模式'),
			_('mvlan=只收 VLAN 组播（不碰账号密码，最省事）；pppoe=接管 45 号 VLAN 拨号（会占用机顶盒的会话）；raw=直接用指定网卡抓'));
		o.default = 'auto';
		o.value('auto', _('自动（先试 mvlan，失败退 pppoe）'));
		o.value('mvlan', _('MVLAN 组播收流'));
		o.value('pppoe', _('PPPoE 接管拨号'));
		o.value('raw', _('直接指定网卡'));

		o = s.option(form.Value, 'pon_iface', _('PON 侧网卡'),
			_('承载 VLAN 的物理网卡，留空则自动查找挂着 45 号 VLAN 的那张网卡'));
		o.placeholder = 'eth1';

		o = s.option(form.Value, 'biz_vid', _('业务 VLAN ID'), _('IPTV 业务 VLAN，深圳电信是 45'));
		o.datatype = 'uinteger';
		o.default = '45';

		o = s.option(form.Value, 'mvlan_vid', _('组播 VLAN ID'), _('MVLAN，深圳电信是 50；这一层上才是裸组播'));
		o.datatype = 'uinteger';
		o.default = '50';

		o = s.option(form.Value, 'raw_dev', _('直接指定网卡'), _('raw 模式用，例如 pon.50 或 br-iptv'));
		o.placeholder = 'pon.50';

		o = s.option(form.Value, 'sniff_dev', _('嗅探接口'),
			_('机顶盒 PPPoE 帧经过的口，一般是桥接机顶盒的那个 br-iptv；留空自动选'));
		o.placeholder = 'br-iptv';

		o = s.option(form.Value, 'sniff_sec', _('嗅探时长（秒）'),
			_('开始嗅探后要在这段时间内重启机顶盒，密码只在认证那一瞬间出现'));
		o.datatype = 'uinteger';
		o.default = '45';

		o = s.option(form.Value, 'pppoe_user', _('PPPoE 账号（IPTV）'),
			_('机顶盒里那个拨号账号，通常是装机单上的 @vod / @iptv 账号，和宽带上网的 @163.gd 不是同一个'));
		o.placeholder = 'xxxx@vod';

		o = s.option(form.Value, 'pppoe_pass', _('PPPoE 密码（IPTV）'), _('明文保存，仅本机可读'));
		o.password = true;

		o = s.option(form.Value, 'pppoe_mac', _('PPPoE 克隆 MAC'),
			_('电信按 MAC 绑定 IPTV 时填机顶盒那个 MAC；不确定就留空'));
		o.placeholder = '70:D5:1E:38:C8:80';

		o = s.option(form.Value, 'auto_probe_sec', _('自动探测时长（秒）'), _('auto 模式在 MVLAN 上等多久判断有没有组播'));
		o.datatype = 'uinteger';
		o.default = '12';

		o = s.option(form.Value, 'duration', _('抓包时长（秒）'),
			_('抓包期间用机顶盒遥控逐个换台，每个台停 2 秒以上；多抓几次会累积补齐'));
		o.datatype = 'uinteger';
		o.default = '60';

		o = s.option(form.Value, 'm3u_path', _('播放列表路径'), _('rtp2httpd 的外部 M3U 指向这里'));
		o.default = '/www/iptv.m3u';

		o = s.option(form.Flag, 'rtp2httpd_sync', _('应用线路时同步 rtp2httpd'),
			_('把 rtp2httpd 的 upstream_interface 改成实际抓包设备，切换模式下必须开'));
		o.default = '1';

		o = s.option(form.Flag, 'reload_rtp2httpd', _('生成后让 rtp2httpd 立即重读'),
			_('给主进程发 SIGHUP，不影响在线客户端'));
		o.default = '1';

		o = s.option(form.Flag, 'enabled', _('定时自动扫描'), _('按间隔自动抓包，慢慢补全频道库'));
		o.default = '0';

		o = s.option(form.Value, 'interval', _('自动扫描间隔（分钟）'), _('0 = 不自动；建议 720'));
		o.datatype = 'uinteger';
		o.default = '720';

		o = s.option(form.TextValue, 'names', _('频道名映射'), _('每行「组播IP 频道名」，例：239.77.0.166 深圳卫视超清'));
		o.rows = 6;
		o.default = '';

		var s2 = m.section(form.NamedSection, 'main', 'iptvscan', _('状态与操作'));
		s2.anonymous = true;

		o = s2.option(form.DummyValue, '_status', _('扫描状态'));
		o.rawhtml = true;
		o.cfgvalue = function() { return statusHtml; };

		o = s2.option(form.DummyValue, '_dev', _('当前抓包设备'));
		o.rawhtml = true;
		o.cfgvalue = function() {
			return '<span class="cbi-value-description">' +
				esc(uci.get('iptvscan', 'main', 'raw_dev') || _('（点「应用线路」后由后端解析）')) + '</span>';
		};

		o = s2.option(form.DummyValue, '_nics', _('本机网卡'));
		o.rawhtml = true;
		o.cfgvalue = function() { return esc(nics.join('  ')); };

		o = s2.option(form.DummyValue, '_play', _('局域网播放地址'));
		o.rawhtml = true;
		o.cfgvalue = function() {
			return '<a href="%s" target="_blank">%s</a>'.format(playUrl, playUrl);
		};

		o = s2.option(form.DummyValue, '_count', _('已收录频道'));
		o.cfgvalue = function() { return String(db.length); };

		o = s2.option(form.DummyValue, '_table', _('频道表'));
		o.rawhtml = true;
		o.cfgvalue = function() { return tableHtml; };

		function runAndReport(cmd, args, title) {
			return fs.exec('/usr/sbin/iptvscan', args || [ cmd ]).then(function(res) {
				var txt = ((res && (res.stdout || res.stderr)) || '').trim() || _('无输出');
				ui.addNotification(null, E('p', {}, title + '：' + txt));
			}).catch(function(err) {
				ui.addNotification(null,
					E('p', {}, title + _('失败：') + (err && err.message ? err.message : err)));
			});
		}

		o = s2.option(form.Button, '_probe', _('线路检测'));
		o.inputtitle = _('检测线路');
		o.inputstyle = 'action';
		o.onclick = function(ev) { ev.preventDefault(); return runAndReport('probe', [ 'probe' ], _('检测结果')); };

		o = s2.option(form.Button, '_apply', _('应用线路'));
		o.inputtitle = _('应用线路');
		o.inputstyle = 'apply';
		o.onclick = function(ev) { ev.preventDefault(); return runAndReport('apply', [ 'apply' ], _('已应用')); };

		o = s2.option(form.DummyValue, '_cred', _('拨号凭据嗅探结果'));
		o.rawhtml = true;
		o.cfgvalue = function() {
			if (!cred.type || cred.type === 'NONE')
				return '<span class="cbi-value-description">' +
					_('未嗅探。PAP 认证是明文可抓；CHAP 只能拿到用户名，密码不可恢复。') + '</span>';

			var t = (cred.type === 'PAP') ? _('PAP（明文）')
				: (cred.type === 'CHAP') ? _('CHAP（仅用户名）') : _('未知');

			return '<span>%s</span>&nbsp;&nbsp;<span>user=%s</span>&nbsp;&nbsp;<span>pass=%s</span>'
				.format(esc(t), esc(cred.user || '-'), esc(cred.pass || '-'));
		};

		o = s2.option(form.Button, '_sniff', _('嗅探机顶盒拨号'));
		o.inputtitle = _('嗅探拨号凭据');
		o.inputstyle = 'action';
		o.onclick = function(ev) {
			ev.preventDefault();
			ui.addNotification(null,
				E('p', {}, _('开始监听 PPPoE，请在 45 秒内把机顶盒断电重启触发重拨；完成后本页自动刷新。')));

			return fs.exec('/usr/sbin/iptvscan', [ 'sniff-bg' ]).then(function() {
				var check = function() {
					fs.read('/tmp/iptvscan.status').then(function(txt) {
						if (parseKv(txt).state === 'running')
							window.setTimeout(check, 2000);
						else
							window.location.reload();
					}).catch(function() { window.setTimeout(check, 2000); });
				};

				window.setTimeout(check, 2000);
			}).catch(function(err) {
				ui.addNotification(null, E('p', {}, _('启动嗅探失败：') + (err && err.message ? err.message : err)));
			});
		};

		o = s2.option(form.Button, '_usecred', _('填入凭据'));
		o.inputtitle = _('填入 PPPoE 字段');
		o.inputstyle = 'action';
		o.onclick = function(ev) {
			ev.preventDefault();
			return runAndReport('use-creds', [ 'use-creds' ], _('已填入'));
		};

		o = s2.option(form.Button, '_scan', _('立即扫描'));
		o.inputtitle = _('开始抓包');
		o.inputstyle = 'apply';
		o.onclick = function(ev) {
			ev.preventDefault();
			ui.addNotification(null, E('p', {}, _('已在后台开始抓包，请现在用遥控器逐个换台；完成后本页自动刷新。')));

			return fs.exec('/usr/sbin/iptvscan', [ 'scan-bg' ]).then(function() {
				var check = function() {
					fs.read('/tmp/iptvscan.status').then(function(txt) {
						if (parseKv(txt).state === 'running')
							window.setTimeout(check, 2000);
						else
							window.location.reload();
					}).catch(function() {
						window.setTimeout(check, 2000);
					});
				};

				window.setTimeout(check, 1500);
			}).catch(function(err) {
				ui.addNotification(null,
					E('p', {}, _('启动抓包失败：') + (err && err.message ? err.message : err)));
			});
		};

		var node = m.render();

		var applyMode = function() {
			var sel = rowByTitle('线路模式');
			var v = sel && sel.querySelector('select') ? sel.querySelector('select').value : 'auto';

			toggleRows([ 'PON 侧网卡', '业务 VLAN ID', '组播 VLAN ID', '自动探测时长（秒）' ], v !== 'raw' && v !== 'pppoe');
			toggleRows([ '业务 VLAN ID', '组播 VLAN ID' ], v === 'pppoe' || v === 'mvlan');
			toggleRows([ 'PPPoE 账号（IPTV）', 'PPPoE 密码（IPTV）', 'PPPoE 克隆 MAC' ], v === 'pppoe' || v === 'auto');
			toggleRows([ '直接指定网卡' ], v === 'raw');
		};

		Promise.resolve(node).then(function() {
			var selRow = rowByTitle('线路模式');
			var sel = selRow && selRow.querySelector('select');

			if (sel) {
				sel.addEventListener('change', applyMode);
				applyMode();
			}
		});

		return node;
	}
});
