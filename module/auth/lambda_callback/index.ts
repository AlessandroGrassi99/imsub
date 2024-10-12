import { Callback, Context, Handler } from 'aws-lambda';
import { DynamoDBClient, QueryCommand } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, TransactWriteCommand } from '@aws-sdk/lib-dynamodb';
import axios from 'axios';

interface DynamoDBAttribute<T> {
  S?: string;
  N?: string;
}

interface StateItem {
  user_id: DynamoDBAttribute<string>;
  message_id: DynamoDBAttribute<string>;
  state: DynamoDBAttribute<string>;
  ttl: DynamoDBAttribute<number>;
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
}

const AWS_REGION = process.env.AWS_REGION!;
const TWITCH_CLIENT_ID = process.env.TWITCH_CLIENT_ID!;
const TWITCH_CLIENT_SECRET = process.env.TWITCH_CLIENT_SECRET!;
const TWITCH_REDIRECT_URL = process.env.TWITCH_REDIRECT_URL!;
const DYNAMODB_TABLE_USERS = process.env.DYNAMODB_TABLE_USERS!;

const ddbClient = new DynamoDBClient({ region: AWS_REGION });
const docClient = DynamoDBDocumentClient.from(ddbClient);

export const handler: Handler<InputEvent, OutputPayload> = async (
  event: InputEvent,
  context: Context
): Promise<OutputPayload> => {
  try {
    console.log('Event', event);
    console.log('Context', context);

    checkState(event.state_item);
    console.log('State checked');

    const tokens = await exchangeCodeForTokens(event.params.code);
    console.log('Code exchanged');
    
    const twitchUserInfo = await fetchTwitchUserInfo(tokens.access_token);
    console.log('User info retrieved');
    
    await saveUserData(
      event.state_item.user_id.S!,
      twitchUserInfo.id,
      tokens.access_token,
      tokens.refresh_token,
      twitchUserInfo,
      tokens.expires_in
    );
    console.log('User data saved');

    console.log('Authorization success');
    return { success: true };
  } catch (err) {
    console.error('Error:', err);
    return { success: false };
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

async function exchangeCodeForTokens(code: string) {
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
      throw new Error('Failed to obtain tokens.');
    }

    return data;
  } catch (error) {
    console.error('Error exchanging code for tokens:', error);
    throw new Error('Failed to obtain tokens.');
  }
}

async function fetchTwitchUserInfo(access_token: string) {
  try {
    const { data } = await axios.get('https://api.twitch.tv/helix/users', {
      headers: {
        'Client-ID': TWITCH_CLIENT_ID,
        Authorization: `Bearer ${access_token}`,
      },
    });

    const userInfo = data.data[0];
    if (!userInfo) {
      throw new Error('Failed to fetch user information.');
    }

    return userInfo;
  } catch (error) {
    console.error('Error fetching Twitch user info:', error);
    throw new Error('Failed to fetch user information.');
  }
}

async function saveUserData(
  user_id: string,
  twitch_id: string,
  access_token: string,
  refresh_token: string,
  twitch_user: any,
  expires_in: number
) {
  const ttl = Math.floor(Date.now() / 1000) + expires_in;

  // Query the GSI to check if the twitch_id is already associated with another user_id.
  const getOldUserCommand = new QueryCommand({
    TableName: DYNAMODB_TABLE_USERS,
    IndexName: 'twitch_id-index',
    KeyConditionExpression: 'twitch_id = :twitch_id',
    ExpressionAttributeValues: {
      ':twitch_id': { S: twitch_id },
    },
    ProjectionExpression: 'user_id',
    Limit: 1
  });

  const oldUserResult = await docClient.send(getOldUserCommand);
  console.log(oldUserResult);
  const transactItems = [];

  // If the twitch_id is associated with a different user, remove it from the old user.
  if (oldUserResult.Items && oldUserResult.Items.length > 0) {
    const oldUserId = oldUserResult.Items[0].user_id.S!;
    if (oldUserId !== user_id) {
      transactItems.push({
        Update: {
          TableName: DYNAMODB_TABLE_USERS,
          Key: { user_id: oldUserId },
          UpdateExpression: 'REMOVE twitch_id, twitch_user, twitch_auth',
          ConditionExpression: 'attribute_exists(user_id)',
        },
      });
    }
  }

  // Update the new user's record with the new twitch_id, twitch_user, and twitch_auth.
  transactItems.push({
    Update: {
      TableName: DYNAMODB_TABLE_USERS,
      Key: { user_id },
      UpdateExpression:
        'SET twitch_id = :twitch_id, twitch_user = :twitch_user, twitch_auth = :twitch_auth',
      ExpressionAttributeValues: {
        ':twitch_id': twitch_id,
        ':twitch_user': twitch_user,
        ':twitch_auth': {
          access_token,
          refresh_token,
          ttl,
        },
      },
      // ConditionExpression: 'attribute_exists(user_id)',
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