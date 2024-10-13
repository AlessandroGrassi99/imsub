import { Context, Handler } from 'aws-lambda';
import { DynamoDBClient, QueryCommand } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, TransactWriteCommand } from '@aws-sdk/lib-dynamodb';
import axios from 'axios';

interface DynamoDBAttribute {
  S?: string;
  N?: string;
}

interface StateItem {
  user_id: DynamoDBAttribute;
  message_id: DynamoDBAttribute;
  state: DynamoDBAttribute;
  ttl: DynamoDBAttribute;
}

interface Params {
  code: string;
  scope: string;
  state: string;
}

interface InputEvent {
  state_item: StateItem;
  params: Params;
}

interface OutputPayload {
  success: boolean;
  user_id: string;
  message_id?: string;
  error?: string;
}

const AWS_REGION = process.env.AWS_REGION!;
const TWITCH_CLIENT_ID = process.env.TWITCH_CLIENT_ID!;
const TWITCH_CLIENT_SECRET = process.env.TWITCH_CLIENT_SECRET!;
const TWITCH_REDIRECT_URL = process.env.TWITCH_REDIRECT_URL!;
const DYNAMODB_TABLE_USERS = process.env.DYNAMODB_TABLE_USERS!;

const ddbClient = new DynamoDBClient({ region: AWS_REGION });
const docClient = DynamoDBDocumentClient.from(ddbClient);

interface TwitchAuth {
  access_token: string;
  access_token_ttl?: string;
  expires_in: number;
  refresh_token: string;
  scope: string[];
  token_type: string;
}

interface TwitchUser {
  id: string;
  login: string;
  display_name: string;
}

export const handler: Handler<InputEvent, OutputPayload> = async (
  event: InputEvent,
  context: Context
): Promise<OutputPayload> => {
  try {
    console.log('Event', event);
    console.log('Context', context);

    checkState(event.state_item);
    console.log('State checked', event.state_item);

    const twitchAuth = await exchangeCodeForTokens(event.params.code);
    console.log('Code exchanged', twitchAuth);
    
    const twitchUser = await fetchTwitchUser(twitchAuth.access_token);
    console.log('User info retrieved', twitchUser);
    
    await saveUserData(
      event.state_item.user_id.S!,
      twitchAuth,
      twitchUser
    );
    console.log('User data saved');

    console.log('Authorization success');
    return { 
      success: true,
      user_id: event.state_item.user_id.S!,
      message_id: event.state_item.message_id.N,
    };
  } catch (err) {
    console.error('Error:', err);
    return { 
      success: false,
      user_id: event.state_item.user_id.S!,
      message_id: event.state_item.message_id.N,
      error: (err as Error).name,
    };
  }
};

function checkState(state: StateItem) {
  let stateTtl: number = parseInt(state.ttl.S!);
  if (isNaN(stateTtl)) {
    console.error('Invalid state TTL:', state.ttl.S);
    throw new Error('Invalid state TTL');
  }

  if (isStateExpired(stateTtl)) {
    console.error('Expired state TTL:', stateTtl);
    throw new Error('Expired state TTL');
  }
}

async function exchangeCodeForTokens(code: string): Promise<TwitchAuth> {
  const tokenURL = 'https://id.twitch.tv/oauth2/token';

  const tokenParams = new URLSearchParams({
    client_id: TWITCH_CLIENT_ID,
    client_secret: TWITCH_CLIENT_SECRET,
    code,
    grant_type: 'authorization_code',
    redirect_uri: TWITCH_REDIRECT_URL,
  });

  try {
    const { data } = await axios.post(tokenURL, tokenParams, {
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
    });

    if (!data.access_token || !data.refresh_token) {
      console.error('Failed to obtain tokens:', data);
      throw new Error('Failed to obtain tokens.');
    }

    const twitchAuth: TwitchAuth = data;
    twitchAuth.access_token_ttl = (Math.floor(Date.now() / 1000) + twitchAuth.expires_in).toString();

    return twitchAuth;
  } catch (error) {
    console.error('Error exchanging code for tokens:', error);
    throw new Error('Failed to obtain tokens.');
  }
}

async function fetchTwitchUser(access_token: string): Promise<TwitchUser> {
  try {
    const { data } = await axios.get('https://api.twitch.tv/helix/users', {
      headers: {
        'Client-ID': TWITCH_CLIENT_ID,
        Authorization: `Bearer ${access_token}`,
      },
    });

    const twitchUser: TwitchUser = data.data[0];
    if (!twitchUser) {
      console.error('Failed to fetch user information.', data);
      throw new Error('Failed to fetch user information.');
    }

    return twitchUser;
  } catch (error) {
    console.error('Error fetching Twitch user info:', error);
    throw new Error('Failed to fetch user information.');
  }
}

async function saveUserData(
  userId: string,
  twitchAuth: TwitchAuth,
  twitchUser: TwitchUser,
) {
  // Query the GSI to check if the twitch_id is already associated with another user_id.
  const getOldUserCommand = new QueryCommand({
    TableName: DYNAMODB_TABLE_USERS,
    IndexName: 'twitch_id-index',
    KeyConditionExpression: 'twitch_id = :twitch_id',
    ExpressionAttributeValues: {
      ':twitch_id': { S: twitchUser.id },
    },
    ProjectionExpression: 'user_id',
    Limit: 1,
  });

  const oldUserResult = await docClient.send(getOldUserCommand);
  const transactItems = [];

  // If the twitch_id is associated with a different user, remove it from the old user.
  if (oldUserResult.Items && oldUserResult.Items.length > 0) {
    const oldUserId = oldUserResult.Items[0].user_id.S!;
    if (oldUserId !== userId) {
      transactItems.push({
        Update: {
          TableName: DYNAMODB_TABLE_USERS,
          Key: { user_id: oldUserId },
          UpdateExpression: 'REMOVE twitch_id, twitch',
          ConditionExpression: 'attribute_exists(user_id)',
        },
      });
    }
  }

  // Update the new user's record with the new twitch_id and twitch map.
  transactItems.push({
    Update: {
      TableName: DYNAMODB_TABLE_USERS,
      Key: { user_id: userId },
      UpdateExpression: 'SET twitch_id = :twitch_id, twitch = :twitch',
      ExpressionAttributeValues: {
        ':twitch_id': twitchUser.id,
        ':twitch': {
          user: twitchUser,
          auth: twitchAuth,
        },
      },
    },
  });

  const transactWriteCommand = new TransactWriteCommand({
    TransactItems: transactItems,
  });

  await docClient.send(transactWriteCommand);
}


function isStateExpired(stateTtl: number, graceSeconds: number = 3): boolean {
  const currentUnixTimeMs = Date.now();
  return stateTtl < (currentUnixTimeMs - graceSeconds * 1000);
}