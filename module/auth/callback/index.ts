import { APIGatewayProxyEvent, APIGatewayProxyResult } from 'aws-lambda';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, GetCommand, DeleteCommand, PutCommand } from '@aws-sdk/lib-dynamodb';
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
      return {
        statusCode: 400,
        body: JSON.stringify({ message: 'Missing query parameters.' }),
      };
    }

    const { code, state, error, error_description } = queryParams;
    console.log(queryParams);
    // Handle errors from Twitch authorization
    if (error) {
      return {
        statusCode: 400,
        body: JSON.stringify({ error, error_description }),
      };
    }

    if (!code || !state) {
      return {
        statusCode: 400,
        body: JSON.stringify({ message: 'Missing code or state parameter.' }),
      };
    }

    // Validate state
    const getStateParams = {
      TableName: DYNAMODB_TABLE_STATES,
      Key: { state },
    };

    const getStateCommand = new GetCommand(getStateParams);
    const getStateResponse = await docClient.send(getStateCommand);
    if (!getStateResponse.Item) {
      return {
        statusCode: 400,
        body: JSON.stringify({ message: 'Invalid or expired state parameter.' }),
      };
    }

    const { user_id } = getStateResponse.Item;

    if (!user_id) {
      return {
        statusCode: 400,
        body: JSON.stringify({ message: 'Invalid state data.' }),
      };
    }

    // Delete the state to prevent reuse
    const deleteStateParams = {
      TableName: DYNAMODB_TABLE_STATES,
      Key: { state },
    };
    const deleteStateCommand = new DeleteCommand(deleteStateParams);
    await docClient.send(deleteStateCommand);

    const tokenURL = 'https://id.twitch.tv/oauth2/token';

    const tokenParams = new URLSearchParams();
    tokenParams.append('client_id', TWITCH_CLIENT_ID);
    tokenParams.append('client_secret', TWITCH_CLIENT_SECRET);
    tokenParams.append('code', code);
    tokenParams.append('grant_type', 'authorization_code');
    tokenParams.append('redirect_uri', TWITCH_REDIRECT_URL);

    const tokenResponse = await axios.post(tokenURL, tokenParams, {
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
    });
    console.log(tokenResponse);

    const {
      access_token,
      refresh_token,
      expires_in,
      scope,
      token_type,
    } = tokenResponse.data;

    if (!access_token || !refresh_token) {
      return {
        statusCode: 500,
        body: JSON.stringify({ message: 'Failed to obtain tokens.' }),
      };
    }

    // Fetch user information from Twitch
    const twitchUserInfoResponse = await axios.get('https://api.twitch.tv/helix/users', {
      headers: {
        'Client-ID': TWITCH_CLIENT_ID,
        Authorization: `Bearer ${access_token}`,
      },
    });
    console.log(twitchUserInfoResponse);

    const twitchUserInfo = twitchUserInfoResponse.data.data[0];
    if (!twitchUserInfo) {
      return {
        statusCode: 500,
        body: JSON.stringify({ message: 'Failed to fetch user information.' }),
      };
    }
    const twitch_id = twitchUserInfo.id!;
    const ttl = Math.floor(Date.now() / 1000) + expires_in; // Current time + expires_in seconds

    const putItemParams = {
      TableName: DYNAMODB_TABLE_USERS,
      Item: {
        user_id,
        twitch_id,
        access_token,
        refresh_token,
        user_info: twitchUserInfo,
        ttl,
      },
    };

    const putItemCommand = new PutCommand(putItemParams);
    await docClient.send(putItemCommand);

    return {
      statusCode: 200,
      body: JSON.stringify({ message: 'Authorization successful.' }),
    };
  } catch (err) {
    console.error('Error during OAuth callback handling:', err);
    return {
      statusCode: 500,
      body: JSON.stringify({ message: 'Internal server error.' }),
    };
  }
};
