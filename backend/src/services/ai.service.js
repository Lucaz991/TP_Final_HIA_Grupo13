const Groq = require('groq-sdk');
const groq = new Groq({ apiKey: process.env.GROQ_API_KEY, timeout: 15000 });

const aiService = {};

aiService.getResponse = async (systemPrompt, userMessage) => {
    const response = await groq.chat.completions.create({
        //openai/gpt-oss-20b
        //groq/compound
        //openai/gpt-oss-120b usar este si se acaban los tokens
        model: 'openai/gpt-oss-20b',
        messages: [
            { role: 'system', content: systemPrompt },
            { role: 'user',   content: userMessage }
        ],
        max_tokens: 500
    });
    return response.choices[0].message.content;
};

module.exports = aiService;