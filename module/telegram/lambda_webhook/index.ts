import { Bot, webhookCallback } from 'grammy';
import { limit } from "@grammyjs/ratelimiter";
import { Redis } from '@upstash/redis';
import { SendMessageCommand, SQSClient } from '@aws-sdk/client-sqs';

const {
    AWS_REGION: region,
    AWS_LAMBDA_FUNCTION_NAME: functionName,
    TELEGRAM_BOT_TOKEN: token,
    TELEGRAM_WEBHOOK_SECRET: secretToken,
    UPSTASH_REDIS_DATABASE_CACHE_ENDPOINT: redisEndpoint,
    UPSTASH_REDIS_DATABASE_CACHE_PASSWORD: redisPassword,
    SQS_SEND_USER_STATUS_URL: sqsSendUserStatusUrl,
    SQS_CHECK_JOIN_REQUEST_URL: sqsCheckJoinRequestUrl,
} = process.env

const sqsClient = new SQSClient({ region });
const bot = new Bot(token!);
const redis = new Redis({
  url: redisEndpoint!,
  token: redisPassword!,
})

bot.use(limit({
  // Allow only 5 messages to be handled every hour
  timeFrame: 3600 * 1000,
  limit: functionName!.includes('dev') ? 5000 : 5,
  storageClient: redis,
  onLimitExceeded: async (ctx, _next) => {
    await ctx.reply('Too many requests! Please try again later.');
  },
  keyGenerator: (ctx) => {
    return ctx.from?.id.toString();
  },
}));

bot.command('start', async (ctx) => {
  console.log('New start command:', ctx.update);

  let message = await ctx.reply('⏳ Loading...');

  try {
    const messageBody = JSON.stringify({
      user_id: ctx.from?.id.toString(),
      message_id: message.message_id.toString(),
      username: ctx.from?.username,
      timestamp: new Date().toISOString(),
    });

    const sendMessageCommand = new SendMessageCommand({
      QueueUrl: sqsSendUserStatusUrl,
      MessageBody: messageBody,
    });

    const response = await sqsClient.send(sendMessageCommand);

    console.log('Message sent to SQS:', response);
  } catch (error) {
    console.error('Error sending message to SQS:', error);
  }
});

bot.on('chat_join_request', async (ctx) => {
  console.log('New chat members:', ctx.update);

  try {
    const messageBody = JSON.stringify({
      user_id: ctx.from?.id.toString(),
      group_id: ctx.chat.id.toString(),
      group_title: ctx.chat.title,
      username: ctx.from?.username,
      timestamp: new Date().toISOString(),
    });

    const sendMessageCommand = new SendMessageCommand({
      QueueUrl: sqsCheckJoinRequestUrl,
      MessageBody: messageBody,
    });

    const response = await sqsClient.send(sendMessageCommand);

    console.log('Message sent to SQS:', response);
  } catch (error) {
    console.error('Error sending message to SQS:', error);
  }
});

export const handler = webhookCallback(bot, 'aws-lambda-async', { secretToken });
