import Bard from '../providers/bard'; // now Google Gemini
import Bing from '../providers/bing'; // now Microsoft Copilot
import Claude2 from '../providers/claude2';
import DeepSeek from '../providers/deepseek';
import Grok from '../providers/grok';
import HuggingChat from '../providers/huggingchat';
import OobaBooga from '../providers/oobabooga';
import OpenAi from '../providers/openai';
import Perplexity from '../providers/perplexity';
import Phind from '../providers/phind';
import Smol from '../providers/smol';
import Together from '../providers/together';
import OpenRouter from '../providers/openrouter';
import Poe from 'providers/poe';
import InflectionPi from 'providers/inflection';

// Retired (sites shut down or discontinued): Claude 1, You.com chat,
// StableChat, Falcon180B space, Perplexity Labs, Lepton Llama, Vercel chat.
// Their files remain in src/providers for reference.
export const allProviders = [
	OpenAi,
	Claude2,
	Bard,
	Perplexity,
	Bing,
	Grok,
	DeepSeek,
	Poe,
	InflectionPi,
	HuggingChat,
	Phind,
	OobaBooga,
	Together,
	OpenRouter,
	Smol,
];
