import { Bot, InlineKeyboard } from 'grammy';
import { Context, Handler } from 'aws-lambda';
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient, 
  PutCommand, 
  QueryCommand, 
  QueryCommandInput 
} from "@aws-sdk/lib-dynamodb";
import { v4 as uuidv4 } from 'uuid';

interface InputEvent {
  user_id: string;
  message_id?: string;
}

interface OutputPayload {
}

const {
  AWS_REGION: awsRegion,
  TELEGRAM_BOT_TOKEN: telegramBotToken,
  TWITCH_REDIRECT_URL: redirectUrl,
  TWITCH_CLIENT_ID: clientId,
  DYNAMODB_TABLE_AUTH_STATES: tableState,
  STATE_TTL_SECONDS: ttlSeconds,
} = process.env;


if (!telegramBotToken) {
  throw new Error('TELEGRAM_BOT_TOKEN is not defined in the environment variables.');
}

const ddbClient = new DynamoDBClient({ region: awsRegion });
const docClient = DynamoDBDocumentClient.from(ddbClient);
const bot = new Bot(telegramBotToken);

export const handler: Handler<InputEvent, OutputPayload> = async (
  input: InputEvent,
  context: Context,
): Promise<OutputPayload> => {
  console.log('Input:', input);
  console.log('Context:', context);
  try {
    if (input.message_id) {
      await bot.api.deleteMessage(input.user_id, parseInt(input.message_id, 10));
    }
  } catch (error) {
    console.error('Error deleting message:', error);
  }

  const state = uuidv4();

  const authUrl = new URL('https://id.twitch.tv/oauth2/authorize');
  const params = new URLSearchParams({
    client_id: clientId!,
    redirect_uri: redirectUrl!,
    response_type: 'code',
    scope: ['user:read:subscriptions', 'channel:read:subscriptions'].join(' '),
    state: state
  });
  authUrl.search = params.toString();

  const inlineKeyboard = new InlineKeyboard()
    .url('Authenticate with Twitch', authUrl.toString());

  const message = await bot.api.sendMessage(input.user_id, `Please authenticate with Twitch`, {
    reply_markup: inlineKeyboard,
  });
  console.log('Message sent:', message);

  await docClient.send(new PutCommand({
    TableName: tableState!,
    Item: {
      state,
      user_id: input.user_id,
      message_id: message.message_id,
      ttl: Math.floor(Date.now() / 1000.0) + parseInt(ttlSeconds!),
    }
  }));
  console.log('State inserted:', state);
  return {};
};
