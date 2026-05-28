import app from './app';
import { logger } from './logger';

const port = process.env.PORT || 8706;

app.listen(port, () => {
  logger.info('startup', { message: `Server is running on port ${port}` });
});
