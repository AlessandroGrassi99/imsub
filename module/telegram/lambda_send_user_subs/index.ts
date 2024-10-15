import { Bot, InlineKeyboard } from 'grammy';
import { Context, Handler } from 'aws-lambda';

interface InputEvent {
  user_id: string;
  message_id: string;
  subscriptions: SubscriptionData[];
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

const { 
  TELEGRAM_BOT_TOKEN: token
} = process.env;

if (!token) {
  throw new Error('TELEGRAM_BOT_TOKEN is not defined in the environment variables.');
}

export const bot = new Bot(token);

export const handler: Handler<InputEvent, void> = async (
  input: InputEvent,
  context: Context,
): Promise<void> => {
  console.log('Input:', input);
  
  try {
    let inlineKeyboard = new InlineKeyboard();
    for (const sub of input.subscriptions) {
      inlineKeyboard.url(sub.broadcaster_name, `https://twitch.tv/${sub.broadcaster_login}`);
    }
    
    if (input.message_id) {
      await bot.api.editMessageReplyMarkup(input.user_id, parseInt(input.message_id), {
        reply_markup: inlineKeyboard
      });
      await bot.api.editMessageText(
        input.user_id, 
        parseInt(input.message_id, 10), 
        `You are subscribed to the following channels:`
      );
    } else {
      await bot.api.sendMessage(
        input.user_id,
        `You are subscribed to the following channels:`,
        { reply_markup: inlineKeyboard },
      );
    }
  
    return;
  } catch (error) {
    console.error('Error processing DynamoDB stream event:', error);
    return;
  }
};