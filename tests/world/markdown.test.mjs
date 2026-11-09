import test from 'node:test';
import assert from 'node:assert/strict';
import { renderMarkdown } from '../../docs/world/markdown.js';

test('HTML in the source is escaped, never passed through', () => {
	const html = renderMarkdown('<script>alert(1)</script> & <img src=x onerror=y>');
	assert.ok(!html.includes('<script>'));
	assert.ok(!html.includes('<img'));
	assert.match(html, /&lt;script&gt;/);
	assert.match(html, /&amp;/);
});

test('headings, bold, italic and inline code', () => {
	const html = renderMarkdown('## Title\n\nSome **bold**, *soft* and `code`.');
	assert.match(html, /<h2>Title<\/h2>/);
	assert.match(html, /<strong>bold<\/strong>/);
	assert.match(html, /<em>soft<\/em>/);
	assert.match(html, /<code>code<\/code>/);
});

test('fenced code keeps its content literal and escaped', () => {
	const html = renderMarkdown('```js\nconst a = "<b>" && **x**;\n```');
	assert.match(html, /<pre><code>/);
	assert.match(html, /&lt;b&gt;/);
	assert.ok(!html.includes('<strong>'));
});

test('bulleted and numbered lists', () => {
	const html = renderMarkdown('- one\n- two\n\n1. first\n2. second');
	assert.match(html, /<ul><li>one<\/li><li>two<\/li><\/ul>/);
	assert.match(html, /<ol><li>first<\/li><li>second<\/li><\/ol>/);
});

test('http links open in a new tab without leaking the opener', () => {
	const html = renderMarkdown('See [the docs](https://example.com/a?b=1&c=2).');
	assert.match(html, /<a href="https:\/\/example\.com\/a\?b=1&amp;c=2" target="_blank" rel="noopener noreferrer">the docs<\/a>/);
});

test('links with a script scheme are left as plain text', () => {
	const html = renderMarkdown('[click](javascript:alert(1))');
	assert.ok(!html.includes('<a '));
	assert.ok(!html.includes('href'));
});

test('a quote in a link target cannot break out of the attribute', () => {
	const html = renderMarkdown('[x](https://example.com/"onmouseover="alert(1))');
	assert.ok(!/href="[^"]*"\s*onmouseover/.test(html));
});

test('a pipe table becomes a table', () => {
	const html = renderMarkdown('| Plan | Cost |\n| --- | --- |\n| A | $1 |\n| B | $2 |');
	assert.match(html, /<table>/);
	assert.match(html, /<th>Plan<\/th>/);
	assert.match(html, /<td>\$2<\/td>/);
});

test('blank-line separated text becomes paragraphs', () => {
	const html = renderMarkdown('First line\nsame paragraph\n\nSecond');
	assert.match(html, /<p>First line<br>same paragraph<\/p><p>Second<\/p>/);
});

test('empty or missing input renders as an empty string', () => {
	assert.equal(renderMarkdown(''), '');
	assert.equal(renderMarkdown(undefined), '');
});
