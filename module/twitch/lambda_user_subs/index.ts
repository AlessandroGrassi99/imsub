import { DynamoDBClient, QueryCommand } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, UpdateCommand } from '@aws-sdk/lib-dynamodb';
import axios, { AxiosResponse } from 'axios';
import { Context, Handler } from 'aws-lambda';

interface InputEvent {
  twitch_id?: string;
  access_token: string;
  broadcaster_id: string[];
  sync_with_database: boolean;
}

interface SubscriptionData {
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
  subscriptions: SubscriptionData[];
  error?: {
    name: string;
    message: string;
  };
}

// Environment Variables
const AWS_REGION = process.env.AWS_REGION!;
const TWITCH_CLIENT_ID = process.env.TWITCH_CLIENT_ID!;
const DYNAMODB_TABLE_USERS = process.env.DYNAMODB_TABLE_USERS!;

const ddbClient = new DynamoDBClient({ region: AWS_REGION });
const docClient = DynamoDBDocumentClient.from(ddbClient);

// Twitch API Configuration
const TWITCH_API_URL = 'https://api.twitch.tv/helix/subscriptions/user';

class InputError extends Error {
  constructor(message?: string) {
    super(message);
    this.name = 'InputError';
  }
}

class TwitchAPIError extends Error {
  constructor(message?: string) {
    super(message);
    this.name = 'TwitchAPIError';
  }
}

class DynamoDBError extends Error {
  constructor(message?: string) {
    super(message);
    this.name = 'DynamoDBError';
  }
}

export const handler: Handler<InputEvent, OutputPayload> = async (
  event: InputEvent,
  context: Context
): Promise<OutputPayload> => {
  console.log('Received event:', event);

  try {
    validateInput(event);

    const { twitch_id, access_token, broadcaster_id, sync_with_database } = event;

    const { subscriptions, errors } = await getSubscriptions(twitch_id!, access_token, broadcaster_id);

    if (sync_with_database) {
      await updateDynamoDB(twitch_id!, subscriptions);
    }

    if (errors.length > 0) {
      console.warn('Subscription check errors:', errors);
      return {
        subscriptions,
        error: {
          name: 'SubscriptionCheckErrors',
          message: errors.join('; '),
        },
      };
    }

    console.log('Successfully retrieved subscriptions.');
    return {
      subscriptions,
    };
  } catch (err: any) {
    console.error(`Error:`, err);
    return {
      subscriptions: [],
      error: {
        name: err.name || 'UnknownError',
        message: err.message || 'An unknown error occurred.',
      },
    };
  }
};

/**
 * Validates the input event.
 */
function validateInput(event: InputEvent): void {
  const { twitch_id, access_token, broadcaster_id } = event;
  if (!twitch_id || !access_token || !broadcaster_id || broadcaster_id.length === 0) {
    throw new InputError('Invalid inputs.');
  }
};

/**
 * Checks subscription for a single broadcaster.
 */
async function checkSubscription(
  headers: any,
  twitch_id: string,
  broadcasterId: string
): Promise<SubscriptionData | null> {
  try {
    const response: AxiosResponse = await axios.get(TWITCH_API_URL, {
      headers,
      params: {
        broadcaster_id: broadcasterId,
        user_id: twitch_id,
      },
    });

    if (response.status === 404) {
      return null;
    }

    if (response.status !== 200 || response.data.data.length === 0) {
      throw new TwitchAPIError(`Invalid response code: ${response}`);
    }

    return response.data.data[0];
  } catch (err) {
    console.error(`Twitch API error for broadcaster_id ${broadcasterId}:`, err);
    throw new TwitchAPIError('Failed to check user subscription.');
  }
}

/**
 * Retrieves subscriptions for all broadcaster IDs.
 */
async function getSubscriptions (
  twitchId: string,
  accessToken: string,
  broadcasterIds: string[]
): Promise<{ subscriptions: SubscriptionData[]; errors: string[] }> {
  const headers = {
    Authorization: `Bearer ${accessToken}`,
    'Client-Id': TWITCH_CLIENT_ID,
  };

  const subscriptionPromises = broadcasterIds.map((bId) =>
    checkSubscription(headers, twitchId, bId)
  );
  const subscriptionsResults = await Promise.allSettled(subscriptionPromises);

  const subscriptions: SubscriptionData[] = [];
  const errors: string[] = [];

  subscriptionsResults.forEach((result, index) => {
    if (result.status === 'fulfilled' && result.value) {
      subscriptions.push(result.value);
    } else if (result.status === 'rejected') {
      errors.push(`Error checking broadcaster_id ${broadcasterIds[index]}: ${result.reason.message}`);
    }
  });

  return { subscriptions, errors };
}

/**
 * Updates the DynamoDB item based on twitch_id by first retrieving the primary key.
 * @param twitchId - The Twitch ID to identify the user.
 * @param subscriptions - The subscription data to update.
 */
async function updateDynamoDB(
  twitchId: string,
  subscriptions: SubscriptionData[]
): Promise<void> {
  try {
    const queryParams = {
      TableName: DYNAMODB_TABLE_USERS,
      IndexName: "twitch_id-index",
      KeyConditionExpression: "twitch_id = :twitchId",
      ExpressionAttributeValues: {
        ":twitchId": { S: twitchId },
      },
      ProjectionExpression: "user_id",
      Limit: 1,
    };

    const queryCommand = new QueryCommand(queryParams);
    const queryResult = await docClient.send(queryCommand);
    console.debug('Query twitch_id', queryResult);

    if (!queryResult.Items || queryResult.Items.length === 0) {
      throw new DynamoDBError(`No item found with twitch_id: ${twitchId}`);
    }

    const userId = queryResult.Items[0].user_id.S!;

    if (!userId) {
      throw new DynamoDBError(`user_id not found for twitch_id: ${twitchId}`);
    }

    const updateParams = {
      TableName: DYNAMODB_TABLE_USERS,
      Key: {
        user_id: userId,
      },
      UpdateExpression: "SET #twitch.#subs = :subsValue",
      ExpressionAttributeNames: {
        "#twitch": "twitch",
        "#subs": "subs",
      },
      ExpressionAttributeValues: {
        ":subsValue": subscriptions,
      },
      ReturnValues: "ALL_NEW" as const, // Returns the updated item
    };

    const updateCommand = new UpdateCommand(updateParams);
    const updateResult = await docClient.send(updateCommand);

    console.log("DynamoDB update result:", updateResult.Attributes);
  } catch (err) {
    console.error("DynamoDB Update Error:", err);
    throw new DynamoDBError("DynamoDB update error.");
  }
}
