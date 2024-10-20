import { Bot } from 'grammy';
import { Context, Handler } from 'aws-lambda';

interface InputEvent {
  user_id: string;
  group_id: string;
  group_title: string;
  subscription?: Subscription;
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

const TELEGRAM_BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN!;

if (!TELEGRAM_BOT_TOKEN) {
  throw new Error('TELEGRAM_BOT_TOKEN is not defined in the environment variables.');
}

const bot = new Bot(TELEGRAM_BOT_TOKEN);

export const handler: Handler<InputEvent, void> = async (
  input: InputEvent,
  context: Context,
): Promise<void> => {
  console.log('Input:', input);
  console.log('Context:', context);

  const user_id = parseInt(input.user_id, 10);
  const group_id = parseInt(input.group_id, 10);

  try {   
    if (input.subscription) {
      await bot.api.approveChatJoinRequest(group_id, user_id);
      console.log('Approved group join request');

    } else {
      await bot.api.declineChatJoinRequest(group_id, user_id);
      console.log('Declined group join request');
      await bot.api.sendMessage(user_id, `Declined group (${input.group_title}) join request because you are not subscribed to the channel.`);
    } 
  } catch (error) {
    console.error('Error sending message:', error);
    throw new Error('Error sending message to user.');
  }
};
