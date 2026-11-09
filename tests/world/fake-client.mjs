/**
 * A stand-in for the Anthropic client, shaped like the one method the World
 * page uses: `client.beta.messages.stream(params, options)`.
 *
 * `replies` is an array (one reply per call, in order) or a function
 * `(params, callIndex) => reply`. A reply may hold:
 *   thinking: string[]   reasoning deltas
 *   text:     string[]   text deltas
 *   blocks:   object[]   extra content blocks (e.g. server_tool_use)
 *   content:  object[]   the final content, when the default assembly is wrong
 *   stop, stopDetails, usage, model
 *   error:    Error      thrown instead of a message
 *   before:   async fn   runs before anything is emitted
 */
export function fakeClient(replies) {
	const calls = [];
	return {
		calls,
		beta: {
			messages: {
				stream(params, options) {
					const index = calls.length;
					calls.push({ params: structuredClone(params), options });
					const reply =
						typeof replies === 'function'
							? replies(params, index)
							: replies[index];
					const handlers = {};
					const fire = (event, ...args) =>
						(handlers[event] || []).forEach((cb) => cb(...args));
					return {
						on(event, cb) {
							(handlers[event] ||= []).push(cb);
							return this;
						},
						async finalMessage() {
							await Promise.resolve();
							if (reply?.before) await reply.before();
							if (options?.signal?.aborted) throw abortError();
							if (!reply)
								throw new Error(
									'fake client: no reply scripted for call ' + index,
								);
							if (reply.error) throw reply.error;
							for (const d of reply.thinking || []) fire('thinking', d);
							for (const b of reply.blocks || []) fire('contentBlock', b);
							for (const d of reply.text || []) fire('text', d);
							const content = reply.content || [
								...(reply.thinking
									? [
											{
												type: 'thinking',
												thinking: reply.thinking.join(''),
												signature: 'sig',
											},
										]
									: []),
								...(reply.blocks || []),
								...(reply.text
									? [{ type: 'text', text: reply.text.join('') }]
									: []),
							];
							return {
								id: 'msg_' + index,
								role: 'assistant',
								model: reply.model || params.model,
								content,
								stop_reason: reply.stop || 'end_turn',
								stop_details: reply.stopDetails || null,
								usage: reply.usage || { input_tokens: 10, output_tokens: 20 },
							};
						},
					};
				},
			},
		},
	};
}

/** An error shaped like the SDK's APIError: a message plus a numeric status. */
export function apiError(status, message = 'api error') {
	const err = new Error(message);
	err.name = 'APIError';
	err.status = status;
	return err;
}

export function abortError() {
	const err = new Error('Request was aborted.');
	err.name = 'APIUserAbortError';
	return err;
}

/** Collects emitted events so a test can assert on what the HUD would be told. */
export function recorder() {
	const events = [];
	const emit = (event) => events.push(event);
	emit.events = events;
	emit.of = (type) => events.filter((e) => e.type === type);
	return emit;
}
