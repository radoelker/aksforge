import mongoose from 'mongoose';
import client from 'prom-client';
import { logger } from './logger';

const mongoConnectionGauge = new client.Gauge({
  name: 'mongo_connection_status',
  help: 'Indicates MongoDB connection status: 1 for connected, 0 for disconnected',
});

const connectDB = async () => {
  try {
    await mongoose.connect(process.env.MONGODB_URI!, {
      retryWrites: false,   // required — Cosmos DB does not support retryable writes
    });
    logger.info('db_read', { error_message: null, route: 'mongodb', status_code: 200 });
    mongoConnectionGauge.set(1);
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    logger.error('db_read', { error_message: errorMessage, route: 'mongodb' });
    mongoConnectionGauge.set(0);
    process.exit(1);
  }
};

mongoose.connection.on('disconnected', () => {
  logger.warn('db_read', { error_message: 'MongoDB disconnected', route: 'mongodb' });
  mongoConnectionGauge.set(0);
});

mongoose.connection.on('reconnected', () => {
  logger.info('db_read', { error_message: null, route: 'mongodb', status_code: 200 });
  mongoConnectionGauge.set(1);
});

export default connectDB;