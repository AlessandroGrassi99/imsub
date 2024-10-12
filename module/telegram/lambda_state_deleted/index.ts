import { Bot, InlineKeyboard } from 'grammy';
import { Callback, Context, DynamoDBStreamEvent, Handler } from 'aws-lambda';

const { TELEGRAM_BOT_TOKEN: token } = process.env;

if (!token) {
  throw new Error('TELEGRAM_BOT_TOKEN is not defined in the environment variables.');
}

export const bot = new Bot(token);

export const handler: Handler<DynamoDBStreamEvent, void> = async (
  event: DynamoDBStreamEvent,
  context: Context,
  callback: Callback
): Promise<void> => {
  try {
    for (const record of event.Records) {
      console.log('Record:', record);
      if (record.eventName === 'REMOVE') {
        const oldImage = record.dynamodb?.OldImage;

        if (!oldImage) {
          console.warn('OldImage is undefined for record:', record);
          continue;
        }
        console.log

        const userIdAttr = oldImage.user_id;
        const messageIdAttr = oldImage.message_id;

        if (!userIdAttr?.S || !messageIdAttr?.N) {
          console.warn('Missing user_id or message_id in OldImage:', oldImage);
          continue; 
        }
        
        let userId: string = userIdAttr.S!;
        let messageId: number = parseInt(messageIdAttr.N!);
        if (isNaN(messageId)) {
          console.warn('Invalid message_id:', messageIdAttr.S);
          continue; 
        }
        
        const inlineKeyboard = new InlineKeyboard()
          .text('Authenticate with Twitch', 'expired-twitch-auth-url');
        await bot.api.editMessageReplyMarkup(userId, messageId, {
            reply_markup: inlineKeyboard
        });
        console.log('Edited message for:', oldImage);
      }
    }
    callback(null, 'Success');
  } catch (error) {
    console.error('Error processing DynamoDB stream event:', error);
    callback(error as Error);
  }
};
