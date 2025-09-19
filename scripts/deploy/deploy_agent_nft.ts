import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { CONTRACTS, deployInBeaconProxy } from "../utils/utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { getNamedAccounts } = hre;
    const { deployer } = await getNamedAccounts();

    console.log("🚀 Deploying AgentNFT with account:", deployer);

    const existingAgentNFT = await hre.deployments.getOrNull(CONTRACTS.AgentNFT.name);
    if (existingAgentNFT) {
        console.log("✅ AgentNFT already deployed at:", existingAgentNFT.address);
        return;
    }

    const verifierDeployment = await hre.deployments.get(CONTRACTS.Verifier.name);
    console.log("📋 Using Verifier at:", verifierDeployment.address);

    console.log("📝 Deploying AgentNFT with Beacon Proxy...");

    const nftName = process.env.ZG_iNFT_NAME || "0G Agent NFT";
    const nftSymbol = process.env.ZG_iNFT_SYMBOL || "0GI";
    const chainURL = process.env.ZG_RPC_URL || "https://evmrpc-testnet.0g.ai";
    const indexerURL = process.env.ZG_INDEXER_URL || "https://indexer-storage-testnet-turbo.0g.ai";
    const storageInfo = JSON.stringify({
        chainURL,
        indexerURL
    });

    const AgentNFTFactory = await hre.ethers.getContractFactory("AgentNFT");
    const agentNFTInitData = AgentNFTFactory.interface.encodeFunctionData("initialize", [
        nftName,
        nftSymbol,
        storageInfo,
        verifierDeployment.address,
        deployer
    ]);

    await deployInBeaconProxy(
        hre,
        CONTRACTS.AgentNFT,
        false,
        [],
        agentNFTInitData
    );

    const agentNFTDeployment = await hre.deployments.get(CONTRACTS.AgentNFT.name);
    console.log("✅ AgentNFT deployed at:", agentNFTDeployment.address);
};

func.tags = ["agentNFT", "core", "prod"];
func.dependencies = ["verifier"];

export default func;