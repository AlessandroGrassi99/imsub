import axios, { AxiosResponse } from 'axios';
import http from 'http';
import https from 'https';
import { Handler } from 'aws-lambda';

interface InputEvent {
  twitch_id?: string;
  access_token: string;
  broadcaster_ids: string[];
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
}

const TWITCH_CLIENT_ID = process.env.TWITCH_CLIENT_ID!;
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

const httpAgent = new http.Agent({ keepAlive: true });
const httpsAgent = new https.Agent({ keepAlive: true });

const axiosInstance = axios.create({
  httpAgent,
  httpsAgent,
});

export const handler: Handler<InputEvent, OutputPayload> = async (
  event: InputEvent,
): Promise<OutputPayload> => {
  console.log('Event:', event);

  try {
    validateInput(event);

    const { twitch_id, access_token, broadcaster_ids: broadcaster_id } = event;

    const { subscriptions, errors } = await getSubscriptions(twitch_id!, access_token, broadcaster_id);

    if (errors.length > 0) {
      console.warn('Subscription check errors:', errors);
      return {
        subscriptions,
      };
    } else if (errors.length === event.broadcaster_ids.length) {
      console.error('Subscription check errors:', errors);
      throw new TwitchAPIError('Failed to check user subscriptions.');
    }
    console.log('Successfully retrieved subscriptions.');
    return {
      subscriptions,
    };
  } catch (err: any) {
    console.error(`Error:`, err);
    throw err;
  }
};

/**
 * Validates the input event.
 */
function validateInput(event: InputEvent): void {
  const { twitch_id, access_token, broadcaster_ids: broadcaster_id } = event;
  if (!twitch_id || !access_token || !broadcaster_id || broadcaster_id.length === 0) {
    throw new InputError('InvalidInputs');
  }
};

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
    if (result.status === 'fulfilled') {
      if (result.value) {
        subscriptions.push(result.value);
      }
    } else if (result.status === 'rejected') {
      errors.push(`Error checking broadcaster_id ${broadcasterIds[index]}: ${result.reason.message}`);
    }
  });

  return { subscriptions, errors };
}

/**
 * Checks subscription for a single broadcaster.
 */
async function checkSubscription(
  headers: any,
  twitch_id: string,
  broadcasterId: string
): Promise<SubscriptionData | null> {
  try {
    const response: AxiosResponse = await axiosInstance.get(TWITCH_API_URL, {
      headers,
      params: {
        broadcaster_id: broadcasterId,
        user_id: twitch_id,
      },
    });

    if (response.status === 404 ) {
      return null;
    }

    if (response.status !== 200 || response.data.data.length === 0) {
      throw new TwitchAPIError(`Invalid response: ${response}`);
    }

    return response.data.data[0];
  } catch (err) {
    console.error(`Twitch API error for broadcaster_id ${broadcasterId}:`, err);
    throw new TwitchAPIError('Failed to check user subscription.');
  }
}