import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { CONTRACTS, deployInBeaconProxy } from "../utils/utils";
import { AttestationConfigStruct } from "../../typechain-types/contracts/verifiers/Verifier";


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

    let attestationContract: string;

    if (process.env.ATTESTATION_CONTRACT) {
        attestationContract = process.env.ATTESTATION_CONTRACT;
        console.log("📋 Using ATTESTATION_CONTRACT from env:", attestationContract);
    } else {
        const teeVerifierDeployment = await hre.deployments.get(CONTRACTS.TEEVerifier.name);
        attestationContract = teeVerifierDeployment.address;
        console.log("📋 Using TEEVerifier as ATTESTATION_CONTRACT:", attestationContract);
    }

    const verifierType = process.env.VERIFIER_TYPE || "0";

    const VerifierFactory = await hre.ethers.getContractFactory("Verifier");
    const attestationConfig: AttestationConfigStruct = {
        oracleType: parseInt(verifierType),
        contractAddress: attestationContract
    };

    console.log("📋 Attestation config:");
    console.log("  Oracle Type:", attestationConfig.oracleType);
    console.log("  Contract Address:", attestationConfig.contractAddress);

    const verifierInitData = VerifierFactory.interface.encodeFunctionData("initialize", [
        [attestationConfig],
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
func.dependencies = ["tee-verifier"];

export default func;