import { APIGatewayProxyHandler } from 'aws-lambda';
import axios from 'axios';
import { DynamoDB } from 'aws-sdk';

const dynamoDb = new DynamoDB.DocumentClient();

export const handler: APIGatewayProxyHandler = async (event) => {
  const code = event.queryStringParameters?.code;
  const state = event.queryStringParameters?.state;

  if (!code || !state) {
    return {
      statusCode: 400,
      body: 'Missing code or state',
    };
  }

  // Retrieve Telegram user ID from stateStore or DynamoDB (implement state validation)
  const telegramUserId = await getTelegramUserIdFromState(state);

  if (!telegramUserId) {
    return {
      statusCode: 400,
      body: 'Invalid state parameter',
    };
  }

  // Exchange code for tokens
  try {
    const tokenResponse = await axios.post(
      'https://id.twitch.tv/oauth2/token',
      null,
      {
        params: {
          client_id: process.env.TWITCH_CLIENT_ID,
          client_secret: process.env.TWITCH_CLIENT_SECRET,
          code,
          grant_type: 'authorization_code',
          redirect_uri: 'https://your-api-gateway-endpoint/oauth2',
        },
      }
    );

    const { access_token, refresh_token, expires_in, scope } = tokenResponse.data;

    // Store tokens in DynamoDB
    await dynamoDb
      .put({
        TableName: process.env.DYNAMODB_TABLE_NAME!,
        Item: {
          telegram_user_id: telegramUserId.toString(),
          access_token,
          refresh_token,
          expires_in,
          scope,
        },
      })
      .promise();

    return {
      statusCode: 200,
      body: 'Authentication successful! You can now return to the Telegram bot.',
    };
  } catch (error) {
    console.error('Error exchanging code for tokens:', error);
    return {
      statusCode: 500,
      body: 'Internal server error',
    };
  }
};

// Implement this function to retrieve the Telegram user ID associated with the state
async function getTelegramUserIdFromState(state: string): Promise<number | null> {
  // For security, you should use a persistent store (e.g., DynamoDB) for state management
  // Here, we return null as a placeholder
  return null;
}
