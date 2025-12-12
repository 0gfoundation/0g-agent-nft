#!/usr/bin/env ts-node

import fs from 'fs';
import path from 'path';
import { execSync } from 'child_process';
import * as dotenv from 'dotenv';

dotenv.config();

interface DeploymentData {
    address: string;
    args?: any[];
    transactionHash?: string;
    abi?: any[];
}

interface ContractConfig {
    contracts: string[];
    description: string;
}

interface VerificationResult {
    contractName: string;
    success: boolean;
    address?: string;
    error?: string;
}

interface HardhatConfig {
    networks?: Record<string, any>;
    external?: {
        deployments?: Record<string, string[]>;
    };
}

const CONTRACT_CONFIGS: Record<string, ContractConfig> = {
    VERIFY_TEE_VERIFIER: {
        contracts: ['TEEVerifier', 'TEEVerifierBeacon', 'TEEVerifierImpl'],
        description: 'TEE Verifier contracts'
    },
    VERIFY_VERIFIER: {
        contracts: ['Verifier', 'VerifierBeacon', 'VerifierImpl'],
        description: 'Verifier contracts'
    },
    VERIFY_AGENT_NFT: {
        contracts: ['AgentNFT', 'AgentNFTBeacon', 'AgentNFTImpl'],
        description: 'Agent NFT contracts'
    },
    VERIFY_AGENT_MARKET: {
        contracts: ['AgentMarket', 'AgentMarketBeacon', 'AgentMarketImpl'],
        description: 'Agent Market contracts'
    }
};

class ContractVerifier {
    private network: string;
    private deploymentsPath: string;

    constructor(network: string) {
        this.network = network;
        this.deploymentsPath = this.getDeploymentsPath(network);
        this.validateSetup();
    }


    private getDeploymentsPath(network: string): string {
        const map: Record<string, string> = {
            zgTestnet: 'zg_testnet',
            zgMainnet: 'zg_mainnet',
        };
        return process.env[`${map[network].toUpperCase()}_DEPLOYMENTS_PATH`] || "";
    }


    private validateSetup(): void {
        if (!fs.existsSync(this.deploymentsPath)) {
            throw new Error(`Deployments directory not found: ${this.deploymentsPath}`);
        }
    }


    private readDeployment(contractName: string): DeploymentData | null {
        const filePath = path.join(this.deploymentsPath, `${contractName}.json`);

        if (!fs.existsSync(filePath)) {
            console.warn(`Warning: Deployment file not found: ${filePath}`);
            return null;
        }

        try {
            const content = fs.readFileSync(filePath, 'utf8');
            return JSON.parse(content) as DeploymentData;
        } catch (error) {
            console.error(`Error reading ${filePath}:`, (error as Error).message);
            return null;
        }
    }


    private formatConstructorArgs(args: any[]): string[] {
        if (!args || args.length === 0) {
            return [];
        }

        return args.map(arg => {
            if (typeof arg === 'string' && arg.startsWith('0x')) {
                return arg;
            }
            if (typeof arg === 'object') {
                return JSON.stringify(arg);
            }
            return `"${arg}"`;
        });
    }


    private buildVerifyCommand(contractName: string, deployment: DeploymentData): string {
        const { address, args = [] } = deployment;
        let command = `npx hardhat verify --network ${this.network}`;

        command += ` ${address}`;

        const formattedArgs = this.formatConstructorArgs(args);
        if (formattedArgs.length > 0) {
            command += ` ${formattedArgs.join(' ')}`;
        }

        return command;
    }

    private async verifyContract(contractName: string): Promise<VerificationResult> {
        console.log(`\nVerifying ${contractName}...`);

        const deployment = this.readDeployment(contractName);
        if (!deployment) {
            return {
                contractName,
                success: false,
                error: 'Deployment file not found'
            };
        }

        console.log(`Address: ${deployment.address}`);
        console.log(`Args: ${JSON.stringify(deployment.args || [])}`);

        const command = this.buildVerifyCommand(contractName, deployment);
        console.log(`Command: ${command}`);

        try {
            const output = execSync(command, {
                encoding: 'utf8',
                stdio: 'pipe',
                timeout: 60000
            });

            console.log(`${contractName} verified successfully!`);
            if (output.trim()) {
                console.log(`Output: ${output.trim()}`);
            }

            return {
                contractName,
                success: true,
                address: deployment.address
            };
        } catch (error) {
            const err = error as any;
            const errorMessage = err.message || 'Unknown error';

            if (errorMessage.includes('Already Verified') ||
                (err.stdout && err.stdout.includes('Already Verified'))) {
                console.log(`${contractName} is already verified.`);
                return {
                    contractName,
                    success: true,
                    address: deployment.address
                };
            }

            console.error(`Failed to verify ${contractName}:`);
            console.error(`Error: ${errorMessage}`);

            if (err.stdout) {
                console.error(`Stdout: ${err.stdout}`);
            }
            if (err.stderr) {
                console.error(`Stderr: ${err.stderr}`);
            }

            return {
                contractName,
                success: false,
                address: deployment.address,
                error: errorMessage
            };
        }
    }

    private async verifyContractGroup(envKey: string): Promise<VerificationResult[]> {
        const config = CONTRACT_CONFIGS[envKey];
        if (!config) {
            console.warn(`Unknown contract group: ${envKey}`);
            return [];
        }

        console.log(`\nVerifying ${config.description}...`);

        const results: VerificationResult[] = [];

        for (let i = 0; i < config.contracts.length; i++) {
            const contractName = config.contracts[i];
            const result = await this.verifyContract(contractName);
            results.push(result);

            if (i < config.contracts.length - 1) {
                console.log('Waiting 3 seconds...');
                await this.delay(3000);
            }
        }

        console.log(`\n${config.description} Results:`);
        results.forEach(({ contractName, success }) => {
            const status = success ? 'SUCCESS' : 'FAILED';
            console.log(`  ${status}: ${contractName}`);
        });

        return results;
    }

    private delay(ms: number): Promise<void> {
        return new Promise(resolve => setTimeout(resolve, ms));
    }

    private getEnabledContractGroups(): string[] {
        return Object.keys(CONTRACT_CONFIGS).filter(key => {
            const envValue = process.env[key];
            return envValue === 'true';
        });
    }

    async run(): Promise<void> {
        console.log('Starting contract verification...');
        console.log(`Network: ${this.network}`);
        console.log(`Deployments path: ${this.deploymentsPath}`);

        const enabledGroups = this.getEnabledContractGroups();

        if (enabledGroups.length === 0) {
            console.log('\nNo contract groups enabled. Set environment variables to enable verification:');
            Object.keys(CONTRACT_CONFIGS).forEach(key => {
                console.log(`  ${key}=true`);
            });
            return;
        }

        console.log(`\nEnabled groups: ${enabledGroups.join(', ')}`);

        const allResults: VerificationResult[] = [];

        for (const envKey of enabledGroups) {
            const results = await this.verifyContractGroup(envKey);
            allResults.push(...results);
        }

        this.printFinalResults(allResults);
    }

    private printFinalResults(results: VerificationResult[]): void {
        console.log('\nFinal Verification Results:');
        console.log('='.repeat(50));

        const successful = results.filter(r => r.success);
        const failed = results.filter(r => !r.success);

        console.log(`Successful: ${successful.length}`);
        successful.forEach(({ contractName, address }) => {
            console.log(`  SUCCESS: ${contractName} (${address})`);
        });

        if (failed.length > 0) {
            console.log(`Failed: ${failed.length}`);
            failed.forEach(({ contractName, address, error }) => {
                console.log(`  FAILED: ${contractName} (${address || 'N/A'}) - ${error || 'Unknown error'}`);
            });
        }

        console.log('\nVerification completed!');

        if (failed.length > 0) {
            process.exit(1);
        }
    }
}

function parseArguments(): string {
    const args = process.argv.slice(2);

    if (args.length === 0) {
        console.error('Usage: ts-node verify-contracts.ts <network>');
        console.error('Example: ts-node verify-contracts.ts zgTestnet');
        process.exit(1);
    }

    return args[0];
}

async function main(): Promise<void> {
    try {
        const network = parseArguments();
        const verifier = new ContractVerifier(network);

        await verifier.run();
    } catch (error) {
        console.error('Script failed:', (error as Error).message);
        process.exit(1);
    }
}

if (require.main === module) {
    main().catch(error => {
        console.error('Unhandled error:', error);
        process.exit(1);
    });
}

export default ContractVerifier;