import { Bot, InlineKeyboard, webhookCallback } from 'grammy';
import { limit } from "@grammyjs/ratelimiter";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, PutCommand } from "@aws-sdk/lib-dynamodb";
import { v4 as uuidv4 } from 'uuid';
import { Redis } from '@upstash/redis';

const {
    AWS_LAMBDA_FUNCTION_NAME: functionName,
    TELEGRAM_BOT_TOKEN: token,
    TELEGRAM_WEBHOOK_SECRET: secretToken,
    TWITCH_REDIRECT_URL: redirectUrl,
    TWITCH_CLIENT_ID: clientId,
    DYNAMODB_TABLE_STATES: tableState,
    STATE_TTL_SECONDS: ttlSeconds,
    UPSTASH_REDIS_DATABASE_CACHE_ENDPOINT: redisEndpoint,
    UPSTASH_REDIS_DATABASE_CACHE_PASSWORD: redisPassword,
} = process.env

export const bot = new Bot(token!);

const dynamoClient = new DynamoDBClient({});
const ddbDocClient = DynamoDBDocumentClient.from(dynamoClient);

const redis = new Redis({
  url: redisEndpoint!,
  token: redisPassword!,
})

bot.use(limit({
  // Allow only 5 messages to be handled every hour
  timeFrame: 3600 * 1000,
  limit: functionName!.includes('dev') ? 5000 : 5,
  storageClient: redis,
  onLimitExceeded: async (ctx, _next) => {
    await ctx.reply('Too many requests! Please try again later.');
  },
  keyGenerator: (ctx) => {
    return ctx.from?.id.toString();
  },
}));

bot.command('start', async (ctx) => {
  const state = uuidv4();

  const scopes = ['user:read:subscriptions', 'channel:read:subscriptions'].join('+');
  const authUrl = `https://id.twitch.tv/oauth2/authorize?client_id=${clientId!}&redirect_uri=${encodeURIComponent(
    redirectUrl!
  )}&response_type=code&scope=${scopes}&state=${state}`;

  const inlineKeyboard = new InlineKeyboard()
    .url('Authenticate with Twitch', authUrl);
  let message = await ctx.reply(`Please authenticate with Twitch`, {
    reply_markup: inlineKeyboard,
  });
  console.log('Message sent:', message);

  await ddbDocClient.send(new PutCommand({
    TableName: tableState!,
    Item: {
      state,
      user_id: ctx.from!.id.toString(),
      message_id: message.message_id,
      ttl: Math.floor(Date.now() / 1000.0) + parseInt(ttlSeconds!),
    }
  }));
  console.log('State inserted:', state);
});

// export const handler: Handler<APIGatewayProxyEventV2, void> = async (
//   event: APIGatewayProxyEventV2,
//   context: Context,
// ): Promise<void> => { 

//   console.log('Event:', event);
//   console.log('Context:', context);
//   await webhookCallback(bot, 'aws-lambda-async', { secretToken });

// }

export const handler = webhookCallback(bot, 'aws-lambda-async', { secretToken });
