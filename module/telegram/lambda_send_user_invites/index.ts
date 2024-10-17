import { Bot, InlineKeyboard } from 'grammy';
import { Context, Handler } from 'aws-lambda';
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient, 
  QueryCommand, 
  QueryCommandInput 
} from "@aws-sdk/lib-dynamodb";

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

interface OutputPayload {
}

class SendingMessageError extends Error {
  constructor(message?: string) {
    super(message);
    this.name = 'SendingMessageError';
  }
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

export const handler: Handler<InputEvent, OutputPayload> = async (
  input: InputEvent,
  context: Context,
): Promise<OutputPayload> => {
  console.log('Input:', input);
  console.log('Context:', context);

  try {   
    if (input.message_id) {
      const deleted = await bot.api.deleteMessage(input.user_id, parseInt(input.message_id, 10));
      console.log('Deleted message:', deleted);
    }
  } catch (error) {
    console.error('Error deleting message:', error);
  }

  const [broadcasterNames1, groupIds1] = await getAllGroupsByTwitchIds(input.subscriptions); 
  console.log(`Groups by twitch_ids:`, broadcasterNames1, groupIds1);
  const [broadcasterNames2, groupIds2] = await filterOutsiderGroups(parseInt(input.user_id, 10), broadcasterNames1, groupIds1);
  console.log(`Groups where user is not in:`, broadcasterNames2, groupIds2);
  const [broadcasterNames3, groupChats] = await getGroupChats(broadcasterNames2, groupIds2);
  console.log(`Group chats:`, groupChats);
  const inlineKeyboard = await buildInlineKeyboard(broadcasterNames3, groupChats);

  try {   
    await bot.api.sendMessage(
      input.user_id,
      `You are now logged in as <a href="https://twitch.tv/${input.twitch_display_name}">${input.twitch_display_name}</a> and subscribed to the following channels. Click the button to join the group.`,
      { reply_markup: inlineKeyboard, parse_mode: 'HTML', link_preview_options: { is_disabled: true } },
    );
  } catch (error) {
    console.error('Error sending message:', error)
    throw new SendingMessageError('Error sending message to user.');
  }
  return {};
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
        data.Items.forEach((item) => {
          if (Array.isArray(item.group_ids)) {
            item.group_ids.forEach((groupId: string) => {
              broadcasterNames.push(broadcasterName);
              groupIds.push(groupId);
            });
          } else {
            console.error(`Invalid group_ids for ${broadcasterName}[${broadcasterId}]:`, item.group_ids);
          }
        });
      }
    } else {
      console.error(`Error querying group_ids for ${broadcasterName}[${broadcasterId}]:`, result.reason);
    }
  });

  return [broadcasterNames, groupIds];
}

async function filterOutsiderGroups(userId: number, broadcasterNames: string[], groupIds: string[]): Promise<[string[], string[]]> {
  const filteredBroadcasterNames: string[] = [];
  const filteredGroupIds: string[] = [];

  const chatMemberPromises = groupIds.map((groupId) => bot.api.getChatMember(groupId, userId));
  const chatMemberPromisesResults = await Promise.allSettled(chatMemberPromises);

  chatMemberPromisesResults.forEach((result, index) => {
    let canJoin = false;
    if (result.status === 'fulfilled') {
      if (result.value.status === 'left') {
        canJoin = true;
      }
    } else {
      console.error(`Error getting group chat ${broadcasterNames[index]}[${groupIds[index]}]:`, result.reason); 
    }

    if (canJoin) {
      filteredBroadcasterNames.push(broadcasterNames[index]);
      filteredGroupIds.push(groupIds[index]);
    }
  });

  return [filteredBroadcasterNames, filteredGroupIds];
}

async function getGroupChats(broadcasterNames: string[], groupIds: string[]): Promise<[string[], any[]]> {
  const groupPromises = groupIds.map((groupId) => bot.api.getChat(groupId));
  const groupPromisesResults = await Promise.allSettled(groupPromises);

  const filteredBroadcasterNames: string[] = [];
  const groupChats: any[] = [];

  groupPromisesResults.forEach((result, index) => {
    if (result.status === 'fulfilled') {
      groupChats.push(result.value);
      filteredBroadcasterNames.push(broadcasterNames[index]);
    } else {
      console.error(`Error getting group chat ${broadcasterNames[index]}[${groupIds[index]}]:`, result.reason);
    }
  });

  return [filteredBroadcasterNames, groupChats];
}

async function buildInlineKeyboard(broadcasterNames: string[], groupChats: any[]): Promise<InlineKeyboard> {
  const inlineKeyboard = new InlineKeyboard();

  const linkPromises = groupChats.map((groupChat) => bot.api.createChatInviteLink(groupChat.id, {
    creates_join_request: true,
    expire_date: Math.floor(Date.now() / 1000) + 86400,
  }));
  
  const linkResults = await Promise.allSettled(linkPromises);

  linkResults.forEach((result, index) => {
    if (result.status === 'fulfilled') {
      const groupLink = result.value;
      const text = `${groupChats[index].title} (${broadcasterNames[index]})`;
      const button = { text, url: groupLink.invite_link };
      inlineKeyboard.row(button);
    } else {
      console.error(`Error creating chat invite link for ${broadcasterNames[index]}[${groupChats[index].id}]:`, result.reason);
    }
  });

  return inlineKeyboard;
}