import { FACTORY_POSTFIX } from "@typechain/ethers-v6/dist/common";
import {
    ContractFactory,
    ContractRunner,
    ethers,
    Signer,
} from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import "hardhat-deploy";
import "hardhat-deploy-ethers";

import * as TypechainTypes from "../../typechain-types";
export let Factories = {} as typeof TypechainTypes;
try {
    Factories = require("../../typechain-types") as typeof TypechainTypes;
} catch (err) {
    // ignore
}

const UPGRADEABLE_BEACON = "UpgradeableBeacon";
const BEACON_PROXY = "BeaconProxy";
export const DEFAULT_ADMIN_ROLE = "0x0000000000000000000000000000000000000000000000000000000000000000";
export const ADMIN_ROLE = ethers.id("ADMIN_ROLE");
export const PAUSER_ROLE = ethers.id("PAUSER_ROLE");
export const UNFROZEN_ROLE = ethers.id("UNFROZEN_ROLE");

interface TypechainFactory<T> {
    new (...args: ConstructorParameters<typeof ContractFactory>): ContractFactory;
    connect: (address: string, runner?: ContractRunner | null) => T;
}

class ContractMeta<T> {
    factory: TypechainFactory<T>;
    name: string;

    constructor(factory: TypechainFactory<T>, name?: string) {
        this.factory = factory;
        this.name = name ?? this.contractName();
    }

    contractName() {
        return this.factory?.name.slice(0, -FACTORY_POSTFIX.length);
    }
}

export const CONTRACTS = {
    Verifier: new ContractMeta(Factories.Verifier__factory),
    AgentNFT: new ContractMeta(Factories.AgentNFT__factory),
    AgentMarket: new ContractMeta(Factories.AgentMarket__factory),
} as const;

export async function deployDirectly(
    hre: HardhatRuntimeEnvironment,
    contract: ContractMeta<unknown>,
    args: unknown[] = []
) {
    const { deployments, getNamedAccounts } = hre;
    const { deployer } = await getNamedAccounts();
    // deploy implementation
    await deployments.deploy(contract.name, {
        from: deployer,
        contract: contract.contractName(),
        args: args,
        log: true,
    });
}

export async function deployInBeaconProxy(
    hre: HardhatRuntimeEnvironment,
    contract: ContractMeta<unknown>,
    onlyBeacon: boolean = false,
    args: unknown[] = [],
    initData: string = "0x"
) {
    const { deployments, getNamedAccounts } = hre;
    const { deployer } = await getNamedAccounts();

    // 1. Deploy implementation
    const implName = `${contract.name}Impl`;
    await deployments.deploy(implName, {
        from: deployer,
        contract: contract.contractName(),
        args: args,
        log: true,
    });
    const implementation = await hre.ethers.getContract(implName);

    // 2. Deploy beacon
    const beaconName = `${contract.name}Beacon`;
    await deployments.deploy(beaconName, {
        from: deployer,
        contract: UPGRADEABLE_BEACON,
        args: [await implementation.getAddress(), deployer],
        log: true,
    });
    const beacon = await hre.ethers.getContract(beaconName);

    if (!onlyBeacon) {
        // 3. Deploy proxy with initialization data
        await deployments.deploy(contract.name, {
            from: deployer,
            contract: BEACON_PROXY,
            args: [await beacon.getAddress(), initData],
            log: true,
        });
    }
}

export async function getTypedContract<T>(
    hre: HardhatRuntimeEnvironment,
    contract: ContractMeta<T>,
    signer?: Signer | string
) {
    const address = await (await hre.ethers.getContract(contract.name)).getAddress();
    if (signer === undefined) {
        signer = (await hre.getNamedAccounts()).deployer;
    }
    if (typeof signer === "string") {
        signer = await hre.ethers.getSigner(signer);
    }
    return contract.factory.connect(address, signer);
}