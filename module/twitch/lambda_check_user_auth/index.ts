import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, GetCommand, UpdateCommand } from '@aws-sdk/lib-dynamodb';
import axios, { AxiosResponse } from 'axios';
import { Context, Handler } from 'aws-lambda';

interface TwitchAuth {
  access_token: string;
  access_token_ttl?: string;
  expires_in?: string;
  refresh_token: string;
  scope: string[];
}

interface TwitchUser {
  id: string;
  login: string;
  display_name: string;
}

interface InputEvent {
  user_id: string;
  deep_check?: boolean; // Defaults to true
  auth?: TwitchAuth;
}

interface OutputPayload {
  valid: boolean;
  refreshed?: boolean;
  old_auth?: TwitchAuth;
  new_auth?: TwitchAuth;
  error?: {
    name: string;
    message: string;
  };
}

class GetTwitchUserError extends Error {
  constructor(message?: string) {
    super(message);
    this.name = 'UserFetchError';
  }
}

class RefreshTokenError extends Error {
  constructor(message?: string) {
    super(message);
    this.name = 'RefreshTokenError';
  }
}

class DynamoDBError extends Error {
  constructor(message?: string) {
    super(message);
    this.name = 'DynamoDBError';
  }
}

// Environment Variables
const AWS_REGION = process.env.AWS_REGION!;
const TWITCH_CLIENT_ID = process.env.TWITCH_CLIENT_ID!;
const TWITCH_CLIENT_SECRET = process.env.TWITCH_CLIENT_SECRET!;
const DYNAMODB_TABLE_USERS = process.env.DYNAMODB_TABLE_USERS!;

const ddbClient = new DynamoDBClient({ region: AWS_REGION });
const docClient = DynamoDBDocumentClient.from(ddbClient);

// Lambda Handler
export const handler: Handler<InputEvent, OutputPayload> = async (
  event: InputEvent,
  context: Context
): Promise<OutputPayload> => {
  try {
    console.log('Event', event);
    console.log('Context', context);

    const useDynamoDB = event.auth === undefined;
    console.log('Use DynamoDB?', useDynamoDB);

    let currentTwitchAuth: TwitchAuth;
    if (useDynamoDB) {
      currentTwitchAuth = await getTwitchAuthFromDynamoDB(event.user_id);
    } else {
      currentTwitchAuth = event.auth!;
    }
    console.log('Current Twitch Auth:', currentTwitchAuth);

    let accessTokenValid = true;
    const deepCheck = event.deep_check !== false;
    console.log('Deep check?', deepCheck);
    if (deepCheck) {
      try {
        await getTwitchUser(currentTwitchAuth.access_token);
      } catch (error) {
        accessTokenValid = false;
      }
    } else {
      // Shallow check: validate the token based on access_token_ttl
      const currentTime = Math.floor(Date.now() / 1000);
      const tokenExpiry = parseInt(currentTwitchAuth.access_token_ttl!, 10);
      accessTokenValid = currentTime < tokenExpiry;
    }
    console.log('Is current access token valid?', accessTokenValid);

    let refreshed = false;
    let oldAuth: TwitchAuth = currentTwitchAuth;
    let newAuth: TwitchAuth = oldAuth;
    if (!accessTokenValid) {
      newAuth = await refreshToken(
        TWITCH_CLIENT_ID,
        TWITCH_CLIENT_SECRET,
        oldAuth.refresh_token
      );

      newAuth.expires_in = oldAuth.expires_in;
      newAuth.access_token_ttl = (Math.floor(Date.now() / 1000) + parseInt(newAuth.expires_in!, 10)).toString();
      console.log('Refreshed Token:', newAuth);
      refreshed = true;

      if (useDynamoDB) {
        await saveTwitchAuthToDynamoDB(event.user_id, newAuth);
        console.log('Saved refreshed authentication:', newAuth);
      }
    }

    return {
      valid: true,
      refreshed,
      old_auth: oldAuth,
      new_auth: newAuth,
    };
  } catch (err) {
    console.error('Error:', err);
    return {
      valid: false,
      error: {
        name: (err as Error).name,
        message: (err as Error).message,
      },
    };
  }
};

/**
 * Fetches the Twitch user using the access token.
 */
async function getTwitchUser(accessToken: string): Promise<TwitchUser> {
  try {
    const { data } = await axios.get('https://api.twitch.tv/helix/users', {
      headers: {
        'Client-ID': TWITCH_CLIENT_ID,
        Authorization: `Bearer ${accessToken}`,
      },
    });

    const twitchUser: TwitchUser = data.data[0];
    if (!twitchUser) {
      console.error('Failed to fetch user information.', data);
      throw new GetTwitchUserError('Failed to fetch user information.');
    }

    return twitchUser;
  } catch (error) {
    console.error('Error fetching Twitch user info:', error);
    throw new GetTwitchUserError('Failed to fetch user information.');
  }
}

/**
 * Refreshes the Twitch access token using the refresh token.
 */
async function refreshToken(
  clientId: string,
  clientSecret: string,
  refreshTokenValue: string
): Promise<TwitchAuth> {
  const url = 'https://id.twitch.tv/oauth2/token';

  const params = new URLSearchParams();
  params.append('grant_type', 'refresh_token');
  params.append('refresh_token', refreshTokenValue);
  params.append('client_id', clientId);
  params.append('client_secret', clientSecret);

  try {
    const response: AxiosResponse<TwitchAuth> = await axios.post(
      url,
      params.toString(),
      {
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      }
    );
    return response.data;
  } catch (error) {
    console.error('Error refreshing token:', error);
    throw new RefreshTokenError('Error refreshing token.');
  }
}

/**
 * Retrieves the TwitchAuth from DynamoDB.
 */
async function getTwitchAuthFromDynamoDB(userId: string): Promise<TwitchAuth> {
  const command = {
    TableName: DYNAMODB_TABLE_USERS,
    Key: {
      user_id: userId,
    },
  };

  try {
    const getCommand = new GetCommand(command);
    const result = await docClient.send(getCommand);
    if (!result.Item || !result.Item.twitch || !result.Item.twitch.auth) {
      throw new DynamoDBError(`No TwitchAuth found for user_id: ${userId}`);
    }
    return result.Item.twitch.auth;
  } catch (error) {
    console.error('Error getting TwitchAuth from DynamoDB:', error);
    throw new DynamoDBError(`Error getting TwitchAuth from DynamoDB: ${(error as Error).message}`);
  }
}

/**
 * Saves the TwitchAuth to DynamoDB.
 */
async function saveTwitchAuthToDynamoDB(
  userId: string,
  twitchAuth: TwitchAuth
): Promise<void> {
  const command = new UpdateCommand({
    TableName: DYNAMODB_TABLE_USERS,
    Key: {
      user_id: userId,
    },
    UpdateExpression: 'SET #twitch.#auth = :authValue',
    ExpressionAttributeNames: {
      '#twitch': 'twitch',
      '#auth': 'auth',
    },
    ExpressionAttributeValues: {
      ':authValue': twitchAuth,
    },
    ReturnValues: "ALL_NEW",
  });

  try {
    const result = await docClient.send(command);
  } catch (error) {
    console.error('Error saving TwitchAuth to DynamoDB:', error);
    throw new DynamoDBError(`Error saving TwitchAuth to DynamoDB: ${(error as Error).message}`);
  }
}
