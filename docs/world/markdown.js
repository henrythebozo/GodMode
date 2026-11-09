/**
 * A small markdown renderer for agent output.
 *
 * Agent text is untrusted (it can quote anything off the web), so everything
 * is HTML-escaped first and only this file's own tags are added afterwards.
 * Links are limited to http(s). It covers what the agents actually write:
 * headings, emphasis, code, lists, quotes, tables, rules and links.
 */
const ESCAPES = {
	'&': '&amp;',
	'<': '&lt;',
	'>': '&gt;',
	'"': '&quot;',
	"'": '&#39;',
};

export function escapeHtml(s) {
	return String(s).replace(/[&<>"']/g, (c) => ESCAPES[c]);
}

const LINK_ATTRS = 'target="_blank" rel="noopener noreferrer"';

function inline(raw) {
	let s = escapeHtml(raw);
	// lift code spans out so nothing inside them is treated as markup
	const codes = [];
	s = s.replace(/`([^`\n]+)`/g, (_, code) => {
		codes.push(code);
		return `\u0000${codes.length - 1}\u0000`;
	});
	s = s.replace(
		/\[([^\]\n]+)\]\((https?:\/\/[^\s)]+)\)/g,
		(_, label, url) => `<a href="${url}" ${LINK_ATTRS}>${label}</a>`,
	);
	// bare URLs; the lead character keeps this off URLs already inside a tag
	s = s.replace(/(^|[\s(])(https?:\/\/[^\s<)]+)/g, (_, lead, url) => {
		const trail = url.match(/[.,;:!?]+$/)?.[0] || '';
		const href = trail ? url.slice(0, -trail.length) : url;
		return `${lead}<a href="${href}" ${LINK_ATTRS}>${href}</a>${trail}`;
	});
	s = s.replace(/\*\*([^*\n]+)\*\*/g, '<strong>$1</strong>');
	s = s.replace(/(^|[^*\w])\*([^*\s][^*\n]*)\*(?!\w)/g, '$1<em>$2</em>');
	return s.replace(/\u0000(\d+)\u0000/g, (_, i) => `<code>${codes[i]}</code>`);
}

const RULE = /^\s*(-{3,}|\*{3,}|_{3,})\s*$/;
const HEADING = /^(#{1,4})\s+(.*?)\s*#*\s*$/;
const BULLET = /^\s*[-*+]\s+(.*)$/;
const NUMBER = /^\s*\d+[.)]\s+(.*)$/;
const QUOTE = /^\s*>\s?(.*)$/;
const FENCE = /^\s*```/;
const TABLE_DIVIDER = /^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?\s*$/;

function cells(line) {
	return line
		.trim()
		.replace(/^\||\|$/g, '')
		.split('|')
		.map((c) => c.trim());
}

export function renderMarkdown(src) {
	// NUL is this file's placeholder for lifted code spans, so none may come in from outside
	const lines = String(src || '')
		.replace(/\u0000/g, '')
		.replace(/\r\n?/g, '\n')
		.split('\n');
	const out = [];
	let para = [];
	const flush = () => {
		if (para.length) out.push(`<p>${para.map(inline).join('<br>')}</p>`);
		para = [];
	};

	for (let i = 0; i < lines.length; i++) {
		const line = lines[i];

		if (FENCE.test(line)) {
			flush();
			const body = [];
			for (i++; i < lines.length && !FENCE.test(lines[i]); i++)
				body.push(lines[i]);
			out.push(`<pre><code>${escapeHtml(body.join('\n'))}</code></pre>`);
			continue;
		}
		if (!line.trim()) {
			flush();
			continue;
		}
		const heading = line.match(HEADING);
		if (heading) {
			flush();
			const level = heading[1].length;
			out.push(`<h${level}>${inline(heading[2])}</h${level}>`);
			continue;
		}
		if (line.includes('|') && TABLE_DIVIDER.test(lines[i + 1] || '')) {
			flush();
			const head = cells(line);
			const rows = [];
			for (i += 2; i < lines.length && lines[i].includes('|'); i++)
				rows.push(cells(lines[i]));
			i--;
			out.push(
				'<table><thead><tr>' +
					head.map((c) => `<th>${inline(c)}</th>`).join('') +
					'</tr></thead><tbody>' +
					rows
						.map(
							(r) =>
								'<tr>' +
								r.map((c) => `<td>${inline(c)}</td>`).join('') +
								'</tr>',
						)
						.join('') +
					'</tbody></table>',
			);
			continue;
		}
		if (RULE.test(line)) {
			flush();
			out.push('<hr>');
			continue;
		}
		const listKind = BULLET.test(line)
			? BULLET
			: NUMBER.test(line)
				? NUMBER
				: null;
		if (listKind) {
			flush();
			const items = [];
			for (; i < lines.length; i++) {
				const item = lines[i].match(listKind);
				if (item) items.push(item[1]);
				// an indented line under an item continues that item
				else if (/^\s+\S/.test(lines[i]) && items.length)
					items[items.length - 1] += ' ' + lines[i].trim();
				else break;
			}
			i--;
			const tag = listKind === BULLET ? 'ul' : 'ol';
			out.push(
				`<${tag}>${items.map((t) => `<li>${inline(t)}</li>`).join('')}</${tag}>`,
			);
			continue;
		}
		if (QUOTE.test(line)) {
			flush();
			const quoted = [];
			for (; i < lines.length && QUOTE.test(lines[i]); i++)
				quoted.push(lines[i].match(QUOTE)[1]);
			i--;
			out.push(`<blockquote>${quoted.map(inline).join('<br>')}</blockquote>`);
			continue;
		}
		para.push(line);
	}
	flush();
	return out.join('');
}
