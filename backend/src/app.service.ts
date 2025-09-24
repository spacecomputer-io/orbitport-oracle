import { Injectable } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { Web3Service } from './web3/web3.service';
import { OrbitportSDK } from '@spacecomputer-io/orbitport-sdk-ts';
import { keccak256, encodeAbiParameters } from 'viem';

@Injectable()
export class AppService {
  private orbitport: OrbitportSDK;

  constructor(private readonly web3Service: Web3Service) {
    // Initialize Orbitport SDK without credentials to use IPFS only
    this.orbitport = new OrbitportSDK({ config: {} });
  }

  getHello(): string {
    return 'Hello World!';
  }

  @Cron(CronExpression.EVERY_MINUTE)
  async updateRandomness() {
    try {
      // Get one random value from IPFS using Orbitport SDK
      const randomValue = await this.fetchRandomValuesFromIPFS();

      // Get current timestamp
      const timestamp = BigInt(Math.floor(Date.now() / 1000)); // Unix timestamp in seconds

      // Create deterministic randomness by hashing the random value with timestamp
      const randomness = this.createDeterministicRandomness(
        randomValue,
        timestamp,
      );

      // Update the feed with the generated randomness
      await this.web3Service.updateFeed(
        0n, // feedId
        randomness,
        timestamp,
      );

      console.log(
        `Updated randomness: ${randomness.toString()}, timestamp: ${timestamp.toString()}`,
      );
    } catch (error) {
      console.error('Failed to update randomness:', error);
      throw error;
    }
  }

  /**
   * Fetch random value from IPFS using Orbitport SDK
   * @returns Random value as string
   */
  private async fetchRandomValuesFromIPFS(): Promise<string> {
    try {
      // Generate one random value using Orbitport SDK
      const result = await this.orbitport.ctrng.random();

      return result.data.data;
    } catch (error) {
      console.error('Failed to fetch random values from IPFS:', error);
      // Fallback: generate a random string locally
      console.warn('Using fallback random string');
      return Math.random().toString(36).substring(2) + Date.now().toString(36);
    }
  }

  /**
   * Create deterministic randomness by hashing random value with timestamp
   * @param randomValue Random value from IPFS as string
   * @param timestamp Current timestamp
   * @returns Deterministic randomness as bigint
   */
  private createDeterministicRandomness(
    randomValue: string,
    timestamp: bigint,
  ): bigint {
    // Encode the random value and timestamp
    const encodedData = encodeAbiParameters(
      [
        { name: 'randomValue', type: 'string' },
        { name: 'timestamp', type: 'uint256' },
      ],
      [randomValue, timestamp],
    );

    // Hash the encoded data using keccak256
    const hash = keccak256(encodedData);

    // Convert hash to bigint (take first 32 bytes to avoid overflow)
    return BigInt(hash.slice(0, 66)); // Remove '0x' and take 64 hex chars (32 bytes)
  }
}
