import { Bot, GrammyError, HttpError, InlineKeyboard, webhookCallback } from 'grammy';
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, PutCommand } from "@aws-sdk/lib-dynamodb";
import {v4 as uuidv4} from 'uuid';

const {
    TELEGRAM_BOT_TOKEN: token,
    TELEGRAM_WEBHOOK_SECRET: secretToken,
    TWITCH_REDIRECT_URL: redirectUrl,
    TWITCH_CLIENT_ID: clientId,
    DYNAMODB_TABLE_STATES: tableState,
    STATE_TTL_SECONDS: ttlSeconds,
} = process.env

export const bot = new Bot(token!);

const dynamoClient = new DynamoDBClient({});
const ddbDocClient = DynamoDBDocumentClient.from(dynamoClient);

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
      ttl: (Math.floor(Date.now() / 1000.0) + parseInt(ttlSeconds!)).toString(),
    }
  }));
  console.log('State inserted:', state);
});

bot.callbackQuery('expired-twitch-auth-url', async (ctx) => {
  await ctx.answerCallbackQuery({
    text: "This link has expired. If you need to authenticate, use the /start command",
  });
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
