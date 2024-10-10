import { APIGatewayProxyEvent, APIGatewayProxyResult } from 'aws-lambda';
import { DynamoDBClient, QueryCommand } from '@aws-sdk/client-dynamodb';
import {
  DynamoDBDocumentClient,
  GetCommand,
  DeleteCommand,
  PutCommand,
  TransactWriteCommand
} from '@aws-sdk/lib-dynamodb';
import axios from 'axios';

const AWS_REGION = process.env.AWS_REGION!;
const TWITCH_CLIENT_ID = process.env.TWITCH_CLIENT_ID!;
const TWITCH_CLIENT_SECRET = process.env.TWITCH_CLIENT_SECRET!;
const TWITCH_REDIRECT_URL = process.env.TWITCH_REDIRECT_URL!;
const DYNAMODB_TABLE_STATES = process.env.DYNAMODB_TABLE_STATES!;
const DYNAMODB_TABLE_USERS = process.env.DYNAMODB_TABLE_USERS!;

const ddbClient = new DynamoDBClient({ region: AWS_REGION });
const docClient = DynamoDBDocumentClient.from(ddbClient);

export const handler = async (
  event: APIGatewayProxyEvent
): Promise<APIGatewayProxyResult> => {
  try {
    const queryParams = event.queryStringParameters;
    if (!queryParams) {
      return badRequest('Missing query parameters.');
    }
    console.log('Query parameters:', queryParams);

    const { code, state } = await parseAndValidateQueryParams(queryParams);
    console.log('Parameters parsed and validated');
    
    const user_id = await validateState(state);
    console.log('State validated');
    
    await deleteState(state);
    console.log('State deleted');
    
    const tokens = await exchangeCodeForTokens(code);
    console.log('Code exchanged');
    
    const twitchUserInfo = await fetchTwitchUserInfo(tokens.access_token);
    console.log('User info retrieved');
    
    await saveUserData(
      user_id,
      twitchUserInfo.id,
      tokens.access_token,
      tokens.refresh_token,
      twitchUserInfo,
      tokens.expires_in
    );
    console.log('User data saved');

    return {
      statusCode: 200,
      body: JSON.stringify({ message: 'Authorization successful.' }),
    };
  } catch (err) {
    console.error('Error during OAuth callback handling:', err);
    return serverError('Internal server error.');
  }
};

async function parseAndValidateQueryParams(queryParams: {
  [name: string]: string | undefined;
}) {
  const { code, state, error, error_description } = queryParams;

  if (error) {
    throw new Error(`Twitch authorization error: ${error_description}`);
  }

  if (!code || !state) {
    throw new Error('Missing code or state parameter.');
  }

  return { code, state };
}

async function validateState(state: string) {
  const getStateCommand = new GetCommand({
    TableName: DYNAMODB_TABLE_STATES,
    Key: { state },
  });
  const { Item } = await docClient.send(getStateCommand);

  if (!Item || !Item.user_id) {
    throw new Error('Invalid or expired state parameter.');
  }

  return Item.user_id;
}

async function deleteState(state: string) {
  const deleteStateCommand = new DeleteCommand({
    TableName: DYNAMODB_TABLE_STATES,
    Key: { state },
  });
  await docClient.send(deleteStateCommand);
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

function badRequest(message: string): APIGatewayProxyResult {
  return {
    statusCode: 400,
    body: JSON.stringify({ message }),
  };
}

function serverError(message: string): APIGatewayProxyResult {
  return {
    statusCode: 500,
    body: JSON.stringify({ message }),
  };
}
