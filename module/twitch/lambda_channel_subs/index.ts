import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { BatchWriteCommand, DynamoDBDocumentClient, PutCommand, UpdateCommand } from '@aws-sdk/lib-dynamodb';
import axios, { AxiosResponse } from 'axios';
import { Context, Handler } from 'aws-lambda';

interface InputEvent {
  access_token: string;
  broadcaster_id: string;
  sync_with_database: boolean;
}

interface SubscriptionData {
  broadcaster_id: string;
  broadcaster_login: string;
  broadcaster_name: string;
  gifter_id: string;
  gifter_login: string;
  gifter_name: string;
  is_gift: boolean;
  tier: string;
  plan_name: string;
  user_id: string;
  user_login: string;
  user_name: string;
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
// const DYNAMODB_TABLE_SUBSCRIPTIONS = process.env.DYNAMODB_TABLE_SUBSCRIPTIONS!;

const ddbClient = new DynamoDBClient({ region: AWS_REGION });
const docClient = DynamoDBDocumentClient.from(ddbClient);

// Twitch API Configuration
const TWITCH_API_URL = 'https://api.twitch.tv/helix/subscriptions';

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

    const { access_token, broadcaster_id, sync_with_database } = event;

    const { subscriptions, errors } = await getSubscriptions(access_token, broadcaster_id);

    // if (sync_with_database) {
    //   await updateDynamoDB(subscriptions);
    // }

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

    console.log(`Successfully retrieved ${subscriptions.length} subscriptions.`);
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
  const { access_token, broadcaster_id } = event;
  if (!access_token || !broadcaster_id) {
    throw new InputError('Invalid inputs.');
  }
}

/**
 * Retrieves all subscribers for the specified broadcaster ID.
 */
async function getSubscriptions(
  accessToken: string,
  broadcasterId: string
): Promise<{ subscriptions: SubscriptionData[]; errors: string[] }> {
  const headers = {
    Authorization: `Bearer ${accessToken}`,
    'Client-Id': TWITCH_CLIENT_ID,
  };

  let subscriptions: SubscriptionData[] = [];
  let errors: string[] = [];
  let cursor: string | undefined = undefined;

  try {
    do {
      const params: any = {
        broadcaster_id: broadcasterId,
        first: 100,
      };
      if (cursor) {
        params.after = cursor;
      }

      const response: AxiosResponse = await axios.get(TWITCH_API_URL, {
        headers,
        params,
      });

      if (response.status !== 200) {
        throw new TwitchAPIError(`Invalid response code: ${response.status}`);
      }

      const data = response.data.data as SubscriptionData[];
      subscriptions = subscriptions.concat(data);

      cursor = response.data.pagination?.cursor;
      console.log(`Retrieved ${subscriptions.length} subscriptions.`);
    } while (cursor);
  } catch (err: any) {
    console.error('Error fetching subscriptions:', err);
    errors.push(err || 'Unknown error');
  }

  return { subscriptions, errors };
}

/**
 * Updates the DynamoDB item for the broadcaster with the list of subscribers.
 * @param broadcasterId - The broadcaster's ID.
 * @param subscriptions - The subscription data to update.
 */
// async function updateDynamoDB(
//   subscriptions: SubscriptionData[]
// ): Promise<void> {
//   try {
//     const BATCH_SIZE = 25;
//     const batches: SubscriptionData[][] = [];
//     for (let i = 0; i < subscriptions.length; i += BATCH_SIZE) {
//       batches.push(subscriptions.slice(i, i + BATCH_SIZE));
//     }

//     for (const batch of batches) {
//       const putRequests = batch.map((subscription) => ({
//         PutRequest: {
//           Item: {
//             user_id: subscription.user_id,
//             broadcaster_id: subscription.broadcaster_id,
//             broadcaster_login: subscription.broadcaster_login,
//             broadcaster_name: subscription.broadcaster_name,
//             gifter_id: subscription.gifter_id,
//             gifter_login: subscription.gifter_login,
//             gifter_name: subscription.gifter_name,
//             is_gift: subscription.is_gift,
//             tier: subscription.tier,
//             plan_name: subscription.plan_name,
//             user_login: subscription.user_login,
//             user_name: subscription.user_name,
//           },
//         },
//       }));

//       const params = {
//         RequestItems: {
//           [DYNAMODB_TABLE_SUBSCRIPTIONS]: putRequests,
//         },
//       };

//       const command = new BatchWriteCommand(params);
//       const response = await docClient.send(command);

//       if (response.UnprocessedItems && Object.keys(response.UnprocessedItems).length > 0) {
//         console.warn('Some items were not processed. Retrying...');
//       }

//       console.log(`Batch of ${batch.length} items written to DynamoDB.`);
//     }

//   } catch (err) {
//     console.error('DynamoDB Update Error:', err);
//     throw new DynamoDBError('DynamoDB update error.');
//   }
// }
