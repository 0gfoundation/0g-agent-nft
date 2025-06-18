import { ethers } from "hardhat";

interface UpgradeConfig {
    upgradeVerifier: boolean;
    upgradeAgentNFT: boolean;
    upgradeAgentMarket: boolean;
    verifierProxyAddress?: string;
    agentNFTProxyAddress?: string;
    agentMarketProxyAddress?: string;
    performSafetyChecks: boolean;
}

async function getBeaconAddress(beaconProxyAddress: string): Promise<string> {
    const BEACON_SLOT = "0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50";
    const provider = ethers.provider;
    const beaconAddressBytes = await provider.getStorage(beaconProxyAddress, BEACON_SLOT);
    return ethers.getAddress("0x" + beaconAddressBytes.slice(26));
}

async function upgradeContract(
    contractName: string,
    proxyAddress: string,
    newImplementationAddress: string
): Promise<boolean> {
    try {
        console.log(`\n=== Upgrading ${contractName} ===`);
        
        // 1. get the beacon address
        const beaconAddress = await getBeaconAddress(proxyAddress);
        console.log(`${contractName} Beacon address:`, beaconAddress);
        
        // 2. get the beacon contract instance
        const beacon = await ethers.getContractAt("UpgradeableBeacon", beaconAddress);
        
        // 3. verify the permission
        const [deployer] = await ethers.getSigners();
        const owner = await beacon.owner();
        if (owner.toLowerCase() !== deployer.address.toLowerCase()) {
            throw new Error(`Not authorized to upgrade ${contractName}. Owner: ${owner}, Deployer: ${deployer.address}`);
        }
        
        // 4. execute the upgrade
        console.log(`Upgrading ${contractName} to:`, newImplementationAddress);
        const upgradeTx = await beacon.upgradeTo(newImplementationAddress);
        await upgradeTx.wait();
        
        // 5. verify the upgrade
        const currentImpl = await beacon.implementation();
        const success = currentImpl.toLowerCase() === newImplementationAddress.toLowerCase();
        
        console.log(`${contractName} upgrade ${success ? 'successful' : 'failed'}`);
        console.log(`Current implementation:`, currentImpl);
        
        return success;
    } catch (error) {
        console.error(`Error upgrading ${contractName}:`, error);
        return false;
    }
}

async function performSafetyChecks(
    contractName: string,
    proxyAddress: string,
    newImplementationAddress: string
): Promise<boolean> {
    try {
        console.log(`\n=== Safety Checks for ${contractName} ===`);
        
        // 1. check if the new implementation contract is deployed
        const code = await ethers.provider.getCode(newImplementationAddress);
        if (code === "0x") {
            console.error(`❌ No code found at implementation address: ${newImplementationAddress}`);
            return false;
        }
        console.log("✅ Implementation contract has code");
        
        // 2. check if the proxy contract exists
        const proxyCode = await ethers.provider.getCode(proxyAddress);
        if (proxyCode === "0x") {
            console.error(`❌ No code found at proxy address: ${proxyAddress}`);
            return false;
        }
        console.log("✅ Proxy contract exists");
        
        const contract = await ethers.getContractAt(contractName, proxyAddress);
        const version = await contract.VERSION();
        console.log("✅ Contract version:", version);
        
        return true;
    } catch (error) {
        console.error(`Safety check failed for ${contractName}:`, error);
        return false;
    }
}

async function main() {
    // configure the upgrade parameters
    const config: UpgradeConfig = {
        upgradeVerifier: true,
        upgradeAgentNFT: true,
        upgradeAgentMarket: true,
        verifierProxyAddress: process.env.VERIFIER_PROXY_ADDRESS,
        agentNFTProxyAddress: process.env.AGENT_NFT_PROXY_ADDRESS,
        agentMarketProxyAddress: process.env.AGENT_MARKET_PROXY_ADDRESS,
        performSafetyChecks: true
    };

    console.log("=== Smart Contract Upgrade Process ===");
    console.log("Configuration:", config);

    const results = {
        verifierUpgrade: false,
        agentNFTUpgrade: false,
        agentMarketUpgrade: false
    };

    try {
        // 1. upgrade Verifier
        if (config.upgradeVerifier) {
            if (!config.verifierProxyAddress) {
                console.error("❌ Verifier proxy address not provided");
                return;
            }

            console.log("\n📋 Deploying new Verifier implementation...");
            const VerifierFactory = await ethers.getContractFactory("Verifier");
            const newVerifierImpl = await VerifierFactory.deploy();
            await newVerifierImpl.waitForDeployment();
            const verifierImplAddress = await newVerifierImpl.getAddress();
            console.log("✅ New Verifier implementation:", verifierImplAddress);

            // safety checks
            if (config.performSafetyChecks) {
                const safetyCheck = await performSafetyChecks(
                    "Verifier",
                    config.verifierProxyAddress,
                    verifierImplAddress
                );
                if (!safetyCheck) {
                    console.error("❌ Verifier safety checks failed");
                    return;
                }
            }

            // execute the upgrade
            results.verifierUpgrade = await upgradeContract(
                "Verifier",
                config.verifierProxyAddress,
                verifierImplAddress
            );
        }

        // 2. upgrade AgentNFT
        if (config.upgradeAgentNFT) {
            if (!config.agentNFTProxyAddress) {
                console.error("❌ AgentNFT proxy address not provided");
                return;
            }

            console.log("\n📋 Deploying new AgentNFT implementation...");
            const AgentNFTFactory = await ethers.getContractFactory("AgentNFT");
            const newAgentNFTImpl = await AgentNFTFactory.deploy();
            await newAgentNFTImpl.waitForDeployment();
            const agentNFTImplAddress = await newAgentNFTImpl.getAddress();
            console.log("✅ New AgentNFT implementation:", agentNFTImplAddress);

            // safety checks
            if (config.performSafetyChecks) {
                const safetyCheck = await performSafetyChecks(
                    "AgentNFT",
                    config.agentNFTProxyAddress,
                    agentNFTImplAddress
                );
                if (!safetyCheck) {
                    console.error("❌ AgentNFT safety checks failed");
                    return;
                }
            }

            // execute the upgrade
            results.agentNFTUpgrade = await upgradeContract(
                "AgentNFT",
                config.agentNFTProxyAddress,
                agentNFTImplAddress
            );
        }

        // 3. upgrade AgentMarket
        if (config.upgradeAgentMarket) {
            if (!config.agentMarketProxyAddress) {
                console.error("❌ AgentMarket proxy address not provided");
                return;
            }

            console.log("\n📋 Deploying new AgentMarket implementation...");
            const AgentMarketFactory = await ethers.getContractFactory("AgentMarket");
            const newAgentMarketImpl = await AgentMarketFactory.deploy();
            await newAgentMarketImpl.waitForDeployment();
            const agentMarketImplAddress = await newAgentMarketImpl.getAddress();
            console.log("✅ New AgentMarket implementation:", agentMarketImplAddress);

            // safety checks
            if (config.performSafetyChecks) {
                const safetyCheck = await performSafetyChecks(
                    "AgentMarket",
                    config.agentMarketProxyAddress,
                    agentMarketImplAddress
                );
                if (!safetyCheck) {
                    console.error("❌ AgentMarket safety checks failed");
                    return;
                }
            }

            // execute the upgrade
            results.agentMarketUpgrade = await upgradeContract(
                "AgentMarket",
                config.agentMarketProxyAddress,
                agentMarketImplAddress
            );
        }

        // 4. final verification
        console.log("\n=== Final Verification ===");
        
        if (config.upgradeVerifier && config.verifierProxyAddress) {
            try {
                const verifier = await ethers.getContractAt("Verifier", config.verifierProxyAddress);
                const version = await verifier.VERSION();
                console.log("✅ Verifier version after upgrade:", version);
            } catch (error) {
                console.warn("⚠️ Could not verify Verifier after upgrade:", error);
            }
        }

        if (config.upgradeAgentNFT && config.agentNFTProxyAddress) {
            try {
                const agentNFT = await ethers.getContractAt("AgentNFT", config.agentNFTProxyAddress);
                const version = await agentNFT.VERSION();
                console.log("✅ AgentNFT version after upgrade:", version);
            } catch (error) {
                console.warn("⚠️ Could not verify AgentNFT after upgrade:", error);
            }
        }

        if (config.upgradeAgentMarket && config.agentMarketProxyAddress) {
            try {
                const agentMarket = await ethers.getContractAt("AgentMarket", config.agentMarketProxyAddress);
                const version = await agentMarket.VERSION();
                console.log("✅ AgentMarket version after upgrade:", version);
            } catch (error) {
                console.warn("⚠️ Could not verify AgentMarket after upgrade:", error);
            }
        }

        // 4. summary
        console.log("\n=== Upgrade Summary ===");
        console.log("Verifier upgrade:", results.verifierUpgrade ? "✅ Success" : "❌ Failed/Skipped");
        console.log("AgentNFT upgrade:", results.agentNFTUpgrade ? "✅ Success" : "❌ Failed/Skipped");
        console.log("AgentMarket upgrade:", results.agentMarketUpgrade ? "✅ Success" : "❌ Failed/Skipped");
        
        const overallSuccess = (!config.upgradeVerifier || results.verifierUpgrade) && 
                              (!config.upgradeAgentNFT || results.agentNFTUpgrade) &&
                              (!config.upgradeAgentMarket || results.agentMarketUpgrade);
        
        console.log("Overall upgrade:", overallSuccess ? "✅ Success" : "❌ Failed");

        if (!overallSuccess) {
            process.exit(1);
        }

    } catch (error) {
        console.error("❌ Upgrade process failed:", error);
        process.exit(1);
    }
}

main()
    .then(() => {
        console.log("🎉 Upgrade process completed successfully");
        process.exit(0);
    })
    .catch((error) => {
        console.error("💥 Upgrade process failed:", error);
        process.exit(1);
    });