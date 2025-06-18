import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { CONTRACTS, deployInBeaconProxy } from "../utils/utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { getNamedAccounts } = hre;
    const { deployer } = await getNamedAccounts();
    
    console.log("🚀 Deploying Verifier with account:", deployer);
    
    const existingVerifier = await hre.deployments.getOrNull(CONTRACTS.Verifier.name);
    if (existingVerifier) {
        console.log("✅ Verifier already deployed at:", existingVerifier.address);
        return;
    }

    console.log("📝 Deploying Verifier with Beacon Proxy...");
    
    const attestationContract = process.env.ATTESTATION_CONTRACT || "0x0000000000000000000000000000000000000000";
    const verifierType = process.env.VERIFIER_TYPE || "0";
    
    const VerifierFactory = await hre.ethers.getContractFactory("Verifier");
    const verifierInitData = VerifierFactory.interface.encodeFunctionData("initialize", [
        attestationContract,
        parseInt(verifierType),
        deployer
    ]);

    await deployInBeaconProxy(
        hre,
        CONTRACTS.Verifier,
        false,  
        [],
        verifierInitData
    );

    const verifierDeployment = await hre.deployments.get(CONTRACTS.Verifier.name);
    console.log("✅ Verifier deployed at:", verifierDeployment.address);
};

func.tags = ["verifier", "core", "prod"];
func.dependencies = [];

export default func;