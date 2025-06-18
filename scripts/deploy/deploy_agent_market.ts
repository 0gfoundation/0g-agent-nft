// deployments/03_deploy_agentMarket.ts
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { CONTRACTS, deployInBeaconProxy } from "../utils/utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { getNamedAccounts } = hre;
    const { deployer } = await getNamedAccounts();
    
    console.log("🚀 Deploying AgentMarket with account:", deployer);
    
    const existingAgentMarket = await hre.deployments.getOrNull(CONTRACTS.AgentMarket.name);
    if (existingAgentMarket) {
        console.log("✅ AgentMarket already deployed at:", existingAgentMarket.address);
        return;
    }

    const agentNFTDeployment = await hre.deployments.get(CONTRACTS.AgentNFT.name);
    console.log("📋 Using AgentNFT at:", agentNFTDeployment.address);

    console.log("📝 Deploying AgentMarket with Beacon Proxy...");
    
    const initialFeeRate = process.env.ZG_INITIAL_FEE_RATE || "1000";

    const AgentMarketFactory = await hre.ethers.getContractFactory("AgentMarket");
    const agentMarketInitData = AgentMarketFactory.interface.encodeFunctionData("initialize", [
        agentNFTDeployment.address,
        parseInt(initialFeeRate),
        deployer
    ]);
    
    await deployInBeaconProxy(
        hre,
        CONTRACTS.AgentMarket,
        false,  
        [],
        agentMarketInitData
    );

    const agentMarketDeployment = await hre.deployments.get(CONTRACTS.AgentMarket.name);
    console.log("✅ AgentMarket deployed at:", agentMarketDeployment.address);
};

func.tags = ["agentMarket", "core", "prod"];
func.dependencies = ["agentNFT"];

export default func;