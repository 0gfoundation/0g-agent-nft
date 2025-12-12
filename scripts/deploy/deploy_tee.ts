import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { CONTRACTS, deployInBeaconProxy } from "../utils/utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { getNamedAccounts } = hre;
    const { deployer } = await getNamedAccounts();

    console.log("🚀 Deploying TEEVerifier with account:", deployer);

    const existingTEEVerifier = await hre.deployments.getOrNull(CONTRACTS.TEEVerifier.name);
    if (existingTEEVerifier) {
        console.log("✅ TEEVerifier already deployed at:", existingTEEVerifier.address);
        return;
    }

    console.log("📝 Deploying TEEVerifier with Beacon Proxy...");

    const oracleAddress = process.env.ORACLE_ADDRESS || "0x04581d192d22510ced643eaced12ef169644811a";

    const TEEVerifierFactory = await hre.ethers.getContractFactory("TEEVerifier");

    const initializeData = TEEVerifierFactory.interface.encodeFunctionData("initialize", [
        deployer,
        oracleAddress
    ]);

    await deployInBeaconProxy(
        hre,
        CONTRACTS.TEEVerifier,
        false,
        [],
        initializeData
    );

    const teeVerifierDeployment = await hre.deployments.get(CONTRACTS.TEEVerifier.name);
    console.log("✅ TEEVerifier deployed at:", teeVerifierDeployment.address);

    const teeVerifier = await hre.ethers.getContractAt("TEEVerifier", teeVerifierDeployment.address);
    const teeOracleAddress = await teeVerifier.teeOracleAddress();

    console.log("🔍 Deployment verification:");
    console.log("  TEE Oracle Address:", teeOracleAddress);
};

func.tags = ["tee-verifier", "core", "prod"];
func.dependencies = [];

export default func;