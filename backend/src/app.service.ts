import { Injectable } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { Web3Service } from './web3/web3.service';

@Injectable()
export class AppService {
  constructor(private readonly web3Service: Web3Service) {}

  getHello(): string {
    return 'Hello World!';
  }

  @Cron(CronExpression.EVERY_MINUTE)
  async updateRandomness() {
    // fetch randomness
    const randomness = 12345n;
    await this.web3Service.updateFeed(
      0n,
      randomness,
      BigInt(new Date().getTime()),
    );
  }
}
