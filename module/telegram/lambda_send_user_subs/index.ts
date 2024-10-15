import { Bot, InlineKeyboard } from 'grammy';
import { Context, Handler } from 'aws-lambda';
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  QueryCommand,
  QueryCommandInput,
} from "@aws-sdk/lib-dynamodb";
import { Chat } from 'grammy/types';

interface InputEvent {
  user_id: string;
  message_id: string;
  twitch_id: string;
  twitch_display_name: string;
  subscriptions: Subscription[];
}

interface Subscription {
  broadcaster_id: string;
  broadcaster_name: string;
  broadcaster_login: string;
  is_gift?: boolean;
  tier?: string;
  gifter_id?: string;
  gifter_login?: string;
  gifter_name?: string;
}

const AWS_REGION = process.env.AWS_REGION!;
const DYNAMODB_TABLE_CREATORS = process.env.DYNAMODB_TABLE_CREATORS!;
const TELEGRAM_BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN!;

if (!TELEGRAM_BOT_TOKEN) {
  throw new Error('TELEGRAM_BOT_TOKEN is not defined in the environment variables.');
}

const ddbClient = new DynamoDBClient({ region: AWS_REGION });
const docClient = DynamoDBDocumentClient.from(ddbClient);
const bot = new Bot(TELEGRAM_BOT_TOKEN);

export const handler: Handler<InputEvent, void> = async (
  input: InputEvent,
  context: Context,
): Promise<void> => {
  console.log('Input:', input);
  
  try {   
    if (input.message_id) {
      await bot.api.deleteMessage(input.user_id, parseInt(input.message_id, 10));
    }

    const [broadcasterNames1, groupIds] = await getAllGroupsByTwitchIds(input.subscriptions);
    const [broadcasterNames2, groupChats] = await getGroupChats(broadcasterNames1, groupIds);
    // TODO: Remove Chats where the user is already in the group
    const inlineKeyboard = await buildInlineKeyboard(broadcasterNames2, groupChats);

    await bot.api.sendMessage(
      input.user_id,
      `You are now logged in as <a href="https://twitch.tv/${input.twitch_display_name}">${input.twitch_display_name}</a> and subscribed to the following channels. Click the button to join the group.`,
      { reply_markup: inlineKeyboard, parse_mode: 'HTML', link_preview_options: { is_disabled: true } },
    );
    
    return;
  } catch (error) {
    console.error('Error:', error);
    return;
  }
};

async function getAllGroupsByTwitchIds(subscriptions: Subscription[]): Promise<[string[], string[]]> {
  const broadcasterNames: string[] = [];
  const groupIds: string[] = [];

  const queryPromises = subscriptions.map((subscription) => {
    const params: QueryCommandInput = {
      TableName: DYNAMODB_TABLE_CREATORS,
      IndexName: "twitch_id_index",
      KeyConditionExpression: "twitch_id = :twitchId",
      ExpressionAttributeValues: {
        ":twitchId": subscription.broadcaster_id,
      },
      ProjectionExpression: "group_ids",
    };

    const command = new QueryCommand(params);
    return docClient.send(command);
  });

  const results = await Promise.allSettled(queryPromises);

  results.forEach((result, index) => {
    const broadcasterName: string = subscriptions[index].broadcaster_name;
    const broadcasterId: string = subscriptions[index].broadcaster_id;
    if (result.status === "fulfilled") {
      const data = result.value;
      console.debug(`data: ${JSON.stringify(data)}`);
      if (data.Items) {
        data.Items.forEach(item => {
          if (Array.isArray(item.group_ids)) {
            for(const groupId of item.group_ids) {
              broadcasterNames.push(broadcasterName);
              groupIds.push(groupId);
            }
          }
        });
      }
    } else {
      console.error(`Error querying group_ids for ${broadcasterName}[${broadcasterId}]:`, result.reason);
    }
  });

  return [broadcasterNames, groupIds];
}

async function getGroupChats(broadcasterNames: string[], groupIds: string[]): Promise<[string[], Chat[]]> {
  const groupPromises = groupIds.map((groupId) => bot.api.getChat(groupId));
  const groupPromisesResults = await Promise.allSettled(groupPromises);

  const groupChats: Chat[] = [];
  groupPromisesResults.forEach((result, index) => {
    if (result.status === 'fulfilled') {
      groupChats.push(result.value);
    } else {
      console.error(`Error getting group chat ${broadcasterNames[index]}[${groupIds[index]}]:`, result.reason);
      broadcasterNames.splice(index, 1);
    }
  });

  return [broadcasterNames, groupChats];
}

async function buildInlineKeyboard(broadcasterNames: string[], groupChats: Chat[]): Promise<InlineKeyboard> {
  let inlineKeyboard = new InlineKeyboard();
  for (const index of Array.from(groupChats, (_, i) => i)) {
    const groupLink = await bot.api.createChatInviteLink(groupChats[index].id, {
      creates_join_request: true,
      expire_date: Math.floor(Date.now() / 1000) + 86400,
    });
    const text = `${groupChats[index].title} (${broadcasterNames[index]})`;
    inlineKeyboard.url(text, groupLink.invite_link);
  }

  return inlineKeyboard;
}
