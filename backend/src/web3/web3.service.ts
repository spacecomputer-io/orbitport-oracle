import { Injectable, OnModuleInit } from '@nestjs/common';
import {
  createWalletClient,
  createPublicClient,
  http,
  encodeAbiParameters,
  type Address,
  type Hash,
  type WalletClient,
  type PublicClient,
} from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import EOFeedManager from '../../abis/EOFeedManager';
import { arbitrumSepolia } from 'viem/chains';

@Injectable()
export class Web3Service implements OnModuleInit {
  private walletClient: WalletClient;
  private publicClient: PublicClient;
  private contractAddress: `0x${string}`;

  onModuleInit() {
    const privateKey = process.env.PRIVATE_KEY;
    const rpcUrl = process.env.RPC_URL;
    const contractAddr = process.env.CONTRACT_ADDRESS;

    if (!privateKey || !rpcUrl || !contractAddr) {
      throw new Error(
        'Missing required environment variables: PRIVATE_KEY, RPC_URL, CONTRACT_ADDRESS',
      );
    }

    // Validate contract address format
    if (!contractAddr.startsWith('0x')) {
      throw new Error('CONTRACT_ADDRESS must start with 0x');
    }

    // Create account from private key
    const account = privateKeyToAccount(privateKey as `0x${string}`);

    // Create public client for reading
    this.publicClient = createPublicClient({
      transport: http(rpcUrl),
      chain: arbitrumSepolia,
    });

    // Create wallet client for transactions
    this.walletClient = createWalletClient({
      account,
      chain: arbitrumSepolia,
      transport: http(rpcUrl),
    });

    this.contractAddress = contractAddr as `0x${string}`;
  }

  async updateFeed(
    feedId: bigint,
    rate: bigint,
    timestamp: bigint,
  ): Promise<Hash> {
    try {
      // Create leaf input data for update (feedId, rate, timestamp)
      const unhashedLeaf = this.encodeLeafData(feedId, rate, timestamp);

      // Create a simple merkle proof (empty for testing since validation is removed)
      const proof: `0x${string}`[] = [];

      // Create leaf input for update
      const leafInput = {
        leafIndex: 0n,
        unhashedLeaf,
        proof,
      };

      // Create verification parameters (simplified for testing)
      const vParams = {
        eventRoot:
          '0x0000000000000000000000000000000000000000000000000000000000000000' as `0x${string}`,
        blockNumber: BigInt(await this.publicClient.getBlockNumber()),
        chainId: await this.publicClient.getChainId(),
        aggregator: this.walletClient.account?.address as Address,
        blockHash:
          '0x0000000000000000000000000000000000000000000000000000000000000000' as `0x${string}`,
        signature: [0n, 0n] as [bigint, bigint], // Empty signature for testing
        apkG2: [0n, 0n, 0n, 0n] as [bigint, bigint, bigint, bigint], // Empty apk for testing
        nonSignersBitmap: '0x' as `0x${string}`,
      };

      // Make contract call to update feed
      const hash = await this.walletClient.writeContract({
        address: this.contractAddress,
        abi: EOFeedManager.abi,
        functionName: 'updateFeed',
        args: [leafInput, vParams],
        chain: arbitrumSepolia,
        account: this.walletClient.account || null,
      });

      return hash;
    } catch (error) {
      const errorMessage =
        error instanceof Error ? error.message : 'Unknown error';
      throw new Error(`Failed to update feed: ${errorMessage}`);
    }
  }

  private encodeLeafData(
    feedId: bigint,
    rate: bigint,
    timestamp: bigint,
  ): `0x${string}` {
    // Encode the leaf data: feedId, rate, timestamp
    return encodeAbiParameters(
      [
        { name: 'feedId', type: 'uint256' },
        { name: 'rate', type: 'uint256' },
        { name: 'timestamp', type: 'uint256' },
      ],
      [feedId, rate, timestamp],
    );
  }
}
