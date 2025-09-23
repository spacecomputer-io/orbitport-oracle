import { Injectable, OnModuleInit } from '@nestjs/common';
import {
  createWalletClient,
  createPublicClient,
  http,
  type Address,
  type Hash,
  type WalletClient,
  type PublicClient,
} from 'viem';
import { privateKeyToAccount } from 'viem/accounts';

@Injectable()
export class Web3Service implements OnModuleInit {
  private walletClient: WalletClient;
  private publicClient: PublicClient;
  private contractAddress: Address;

  onModuleInit() {
    const privateKey = process.env.PRIVATE_KEY;
    const rpcUrl = process.env.RPC_URL;
    const contractAddr = process.env.CONTRACT_ADDRESS;

    if (!privateKey || !rpcUrl || !contractAddr) {
      throw new Error(
        'Missing required environment variables: PRIVATE_KEY, RPC_URL, CONTRACT_ADDRESS',
      );
    }

    // Create account from private key
    const account = privateKeyToAccount(privateKey as `0x${string}`);

    // Create public client for reading
    this.publicClient = createPublicClient({
      transport: http(rpcUrl),
    });

    // Create wallet client for transactions
    this.walletClient = createWalletClient({
      account,
      transport: http(rpcUrl),
    });

    this.contractAddress = contractAddr as Address;
  }

  async updateFeed(feedData: string): Promise<Hash> {
    try {
      // Make contract call to update feed
      const hash = await this.walletClient.writeContract({
        address: this.contractAddress as `0x${string}`,
        abi: [
          {
            name: 'updateFeed',
            type: 'function',
            stateMutability: 'nonpayable',
            inputs: [
              {
                name: 'data',
                type: 'string',
              },
            ],
            outputs: [],
          },
        ],
        functionName: 'updateFeed',
        args: [feedData],
      });

      return hash;
    } catch (error) {
      const errorMessage =
        error instanceof Error ? error.message : 'Unknown error';
      throw new Error(`Failed to update feed: ${errorMessage}`);
    }
  }
}
