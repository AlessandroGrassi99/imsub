import { Bot, webhookCallback } from 'grammy';
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, PutCommand } from "@aws-sdk/lib-dynamodb";
import {v4 as uuidv4} from 'uuid';

const {
    TELEGRAM_BOT_TOKEN: token,
    TELEGRAM_WEBHOOK_SECRET: secretToken,
    TWITCH_REDIRECT_URL: redirectUrl,
    TWITCH_CLIENT_ID: clientId,
    DYNAMODB_TABLE_STATE: tableState,
} = process.env

export const bot = new Bot(token!);

const dynamoClient = new DynamoDBClient({});
const ddbDocClient = DynamoDBDocumentClient.from(dynamoClient);

const TTL_SECONDS = 600; 

bot.command('start', async (ctx) => {
  const state = uuidv4();

  await ddbDocClient.send(new PutCommand({
    TableName: tableState!,
    Item: {
      state,
      user_id: ctx.from!.id.toString(),
      ttl: Math.floor(Date.now() / 1000) + TTL_SECONDS,
    }
  }));

  const scopes = ['user:read:subscriptions', 'channel:read:subscriptions'].join('+');
  const authUrl = `https://id.twitch.tv/oauth2/authorize?client_id=${clientId!}&redirect_uri=${encodeURIComponent(
    redirectUrl!
  )}&response_type=code&scope=${scopes}&state=${state}`;

  await ctx.reply(`Please authenticate with Twitch: ${authUrl}`);
});

export const handler = webhookCallback(bot, 'aws-lambda-async', { secretToken });
