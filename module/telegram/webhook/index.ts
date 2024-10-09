import { Bot, webhookCallback } from 'grammy';
import { randomBytes } from 'crypto';

const {
    TELEGRAM_BOT_TOKEN: token,
    TELEGRAM_WEBHOOK_SECRET: secretToken,
    TWITCH_REDIRECT_URL: redirectUrl,
    TWITCH_CLIENT_ID: clientId,
} = process.env

export const bot = new Bot(token!);

const stateStore: { [key: string]: number } = {};

bot.command('start', async (ctx) => {
  const state = randomBytes(16).toString('hex'); // Generate a CSRF token
  stateStore[state] = ctx.from?.id || 0;

  const scopes = ['user:read:subscriptions', 'channel:read:subscriptions'].join('+');
  const authUrl = `https://id.twitch.tv/oauth2/authorize?client_id=${clientId!}&redirect_uri=${encodeURIComponent(
    redirectUrl!
  )}&response_type=code&scope=${scopes}&state=${state}`;

  await ctx.reply(`Please authenticate with Twitch: ${authUrl}`);
});

// bot.on('message', async ctx => {
//     await ctx.reply('Hi there!');
// });

export const handler = webhookCallback(bot, 'aws-lambda-async', { secretToken });