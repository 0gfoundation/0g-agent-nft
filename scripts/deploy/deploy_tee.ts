import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { CONTRACTS, deployInBeaconProxy } from "../utils/utils";

interface TrustedMeasurementsStruct {
    mrtd: string;
    rtmr0: string;
    rtmr1: string;
    rtmr2: string;
    rtmr3: string;
}

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

    const tdxQuote = process.env.TDX_QUOTE || "0x00"; // mock quote

    const trustedMeasurements: TrustedMeasurementsStruct = {
        mrtd: process.env.TRUSTED_MRTD || "0x0000000000000000000000000000000000000000000000000000000000000000",
        rtmr0: process.env.TRUSTED_RTMR0 || "0x0000000000000000000000000000000000000000000000000000000000000000",
        rtmr1: process.env.TRUSTED_RTMR1 || "0x0000000000000000000000000000000000000000000000000000000000000000",
        rtmr2: process.env.TRUSTED_RTMR2 || "0x0000000000000000000000000000000000000000000000000000000000000000",
        rtmr3: process.env.TRUSTED_RTMR3 || "0x0000000000000000000000000000000000000000000000000000000000000000"
    };

    console.log("📋 Using trusted measurements:");
    console.log("  MRTD:", trustedMeasurements.mrtd);
    console.log("  RTMR0:", trustedMeasurements.rtmr0);
    console.log("  RTMR1:", trustedMeasurements.rtmr1);
    console.log("  RTMR2:", trustedMeasurements.rtmr2);
    console.log("  RTMR3:", trustedMeasurements.rtmr3);

    const TEEVerifierFactory = await hre.ethers.getContractFactory("TEEVerifier");

    const initializeData = TEEVerifierFactory.interface.encodeFunctionData("initialize", [
        tdxQuote,
        trustedMeasurements
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
    const isVerified = await teeVerifier.verified();
    const teeAddress = await teeVerifier.teeAddress();

    console.log("🔍 Deployment verification:");
    console.log("  Verified:", isVerified);
    console.log("  TEE Address:", teeAddress);
};

func.tags = ["tee-verifier", "core", "prod"];
func.dependencies = [];

export default func;