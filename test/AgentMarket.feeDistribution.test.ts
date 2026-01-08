import { expect } from "chai";
import { ethers } from "hardhat";
import { AgentNFT, AgentMarket, Verifier } from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("AgentMarket - Fee Distribution", function () {
  let agentNFT: AgentNFT;
  let agentMarket: AgentMarket;
  let verifier: Verifier;
  let admin: SignerWithAddress;
  let partner: SignerWithAddress; // 合作方 (如 Dolly)
  let seller: SignerWithAddress;
  let buyer: SignerWithAddress;

  const FEE_RATE = 250n; // 2.5%
  const PARTNER_FEE_RATE = 4000n; // 40% of total fee

  beforeEach(async function () {
    [admin, partner, seller, buyer] = await ethers.getSigners();

    // Deploy Verifier
    const VerifierFactory = await ethers.getContractFactory("Verifier");
    const verifierContract = await VerifierFactory.deploy();
    await verifierContract.waitForDeployment();
    verifier = verifierContract as unknown as Verifier;

    // Deploy AgentNFT with proxy
    const AgentNFTFactory = await ethers.getContractFactory("AgentNFT");
    const agentNFTImpl = await AgentNFTFactory.deploy();
    await agentNFTImpl.waitForDeployment();

    const nftInitData = AgentNFTFactory.interface.encodeFunctionData("initialize", [
      "Test NFT",
      "TNFT",
      JSON.stringify({ test: "data" }),
      await verifier.getAddress(),
      admin.address
    ]);

    const BeaconFactory = await ethers.getContractFactory("UpgradeableBeacon");
    const nftBeacon = await BeaconFactory.deploy(await agentNFTImpl.getAddress(), admin.address);
    await nftBeacon.waitForDeployment();

    const BeaconProxyFactory = await ethers.getContractFactory("BeaconProxy");
    const nftProxy = await BeaconProxyFactory.deploy(await nftBeacon.getAddress(), nftInitData);
    await nftProxy.waitForDeployment();

    agentNFT = AgentNFTFactory.attach(await nftProxy.getAddress()) as unknown as AgentNFT;

    // Deploy AgentMarket with proxy
    const AgentMarketFactory = await ethers.getContractFactory("AgentMarket");
    const agentMarketImpl = await AgentMarketFactory.deploy();
    await agentMarketImpl.waitForDeployment();

    const marketInitData = AgentMarketFactory.interface.encodeFunctionData("initialize", [
      await agentNFT.getAddress(),
      FEE_RATE,
      admin.address,
      0,
      0
    ]);

    const marketBeacon = await BeaconFactory.deploy(await agentMarketImpl.getAddress(), admin.address);
    await marketBeacon.waitForDeployment();

    const marketProxy = await BeaconProxyFactory.deploy(await marketBeacon.getAddress(), marketInitData);
    await marketProxy.waitForDeployment();

    agentMarket = AgentMarketFactory.attach(await marketProxy.getAddress()) as unknown as AgentMarket;

    // Grant MINTER_ROLE to both admin and AgentMarket
    const MINTER_ROLE = await agentNFT.MINTER_ROLE();
    await agentNFT.connect(admin).grantRole(MINTER_ROLE, admin.address);
    await agentNFT.connect(admin).grantRole(MINTER_ROLE, await agentMarket.getAddress());
  });

  describe("Partner Fee Rate Management", function () {
    it("Should set partner fee rate", async function () {
      await expect(
        agentMarket.connect(admin).setPartnerFeeRate(partner.address, PARTNER_FEE_RATE)
      )
        .to.emit(agentMarket, "PartnerFeeRateUpdated")
        .withArgs(partner.address, 0n, PARTNER_FEE_RATE);

      expect(await agentMarket.getPartnerFeeRate(partner.address)).to.equal(PARTNER_FEE_RATE);
    });

    it("Should update partner fee rate", async function () {
      await agentMarket.connect(admin).setPartnerFeeRate(partner.address, PARTNER_FEE_RATE);

      const newRate = 5000n; // 50%
      await expect(
        agentMarket.connect(admin).setPartnerFeeRate(partner.address, newRate)
      )
        .to.emit(agentMarket, "PartnerFeeRateUpdated")
        .withArgs(partner.address, PARTNER_FEE_RATE, newRate);

      expect(await agentMarket.getPartnerFeeRate(partner.address)).to.equal(newRate);
    });

    it("Should revert if fee rate exceeds 100%", async function () {
      await expect(
        agentMarket.connect(admin).setPartnerFeeRate(partner.address, 10001n)
      ).to.be.revertedWith("Fee share rate too high");
    });

    it("Should revert if partner address is zero", async function () {
      await expect(
        agentMarket.connect(admin).setPartnerFeeRate(ethers.ZeroAddress, PARTNER_FEE_RATE)
      ).to.be.revertedWith("Invalid partner address");
    });

    it("Should revert if non-admin tries to set fee rate", async function () {
      await expect(
        agentMarket.connect(partner).setPartnerFeeRate(partner.address, PARTNER_FEE_RATE)
      ).to.be.reverted;
    });

    it("Should return 0 for partner without fee rate", async function () {
      expect(await agentMarket.getPartnerFeeRate(partner.address)).to.equal(0);
    });
  });

  describe("Fee Distribution Without Partner", function () {
    it("Should collect all fees to platform when NFT has no creator", async function () {
      const tokenId = await agentNFT.connect(admin)["mintWithRole(address)"]
        .staticCall(seller.address);

      const tx = await agentNFT.connect(admin)["mintWithRole(address)"](seller.address);
      await tx.wait();

      expect(await agentNFT.ownerOf(tokenId)).to.equal(seller.address);

      // Deposit for buyer
      const price = ethers.parseEther("100");
      await agentMarket.connect(buyer).deposit(buyer.address, { value: price });

      // Create and fulfill order
      const order = await createOrder(tokenId, price, seller);
      const offer = await createOffer(tokenId, price, buyer);

      await agentNFT.connect(seller).approve(await agentMarket.getAddress(), tokenId);
      await agentMarket.connect(admin).fulfillOrder(order, offer, []);

      // Calculate expected fees
      const expectedFee = (price * FEE_RATE) / 10000n;

      // All fees should go to platform
      expect(await agentMarket.getFeeBalance(ethers.ZeroAddress)).to.equal(expectedFee);
      expect(await agentMarket.getPartnerFeeBalance(partner.address, ethers.ZeroAddress)).to.equal(0);
    });

    it("Should collect all fees to platform when creator has 0% fee rate", async function () {
      // Mint NFT with creator but without setting fee rate
      const tokenId = await agentNFT.connect(admin)["mintWithRole(address,string,address)"]
        .staticCall(seller.address, "", partner.address);

      const tx = await agentNFT.connect(admin)["mintWithRole(address,string,address)"](
        seller.address,
        "",
        partner.address
      );
      await tx.wait();

      // 验证 NFT 已经被铸造
      expect(await agentNFT.ownerOf(tokenId)).to.equal(seller.address);

      // Deposit for buyer
      const price = ethers.parseEther("100");
      await agentMarket.connect(buyer).deposit(buyer.address, { value: price });

      // Create and fulfill order
      const order = await createOrder(tokenId, price, seller);
      const offer = await createOffer(tokenId, price, buyer);

      await agentNFT.connect(seller).approve(await agentMarket.getAddress(), tokenId);
      await agentMarket.connect(admin).fulfillOrder(order, offer, []);

      // Calculate expected fees
      const expectedFee = (price * FEE_RATE) / 10000n;

      // All fees should still go to platform
      expect(await agentMarket.getFeeBalance(ethers.ZeroAddress)).to.equal(expectedFee);
      expect(await agentMarket.getPartnerFeeBalance(partner.address, ethers.ZeroAddress)).to.equal(0);
    });
  });

  describe("Fee Distribution With Partner", function () {
    beforeEach(async function () {
      // Set partner fee rate
      await agentMarket.connect(admin).setPartnerFeeRate(partner.address, PARTNER_FEE_RATE);
    });

    it("Should distribute fees between platform and partner", async function () {
      // Mint NFT with creator
      const tokenId = await agentNFT.connect(admin)["mintWithRole(address,string,address)"]
        .staticCall(seller.address, "", partner.address);

      const tx = await agentNFT.connect(admin)["mintWithRole(address,string,address)"](
        seller.address,
        "",
        partner.address
      );
      await tx.wait();

      expect(await agentNFT.ownerOf(tokenId)).to.equal(seller.address);

      // Deposit for buyer
      const price = ethers.parseEther("100");
      await agentMarket.connect(buyer).deposit(buyer.address, { value: price });

      // Create and fulfill order
      const order = await createOrder(tokenId, price, seller);
      const offer = await createOffer(tokenId, price, buyer);

      await agentNFT.connect(seller).approve(await agentMarket.getAddress(), tokenId);
      await agentMarket.connect(admin).fulfillOrder(order, offer, []);

      // Calculate expected fees
      // price = 100, fee rate = 2.5%, total fee = 2.5
      // partner gets 40% of 2.5 = 1.0
      // platform gets 60% of 2.5 = 1.5
      const totalFee = (price * FEE_RATE) / 10000n;
      const expectedPartnerFee = (totalFee * PARTNER_FEE_RATE) / 10000n;
      const expectedPlatformFee = totalFee - expectedPartnerFee;

      expect(await agentMarket.getFeeBalance(ethers.ZeroAddress)).to.equal(expectedPlatformFee);
      expect(await agentMarket.getPartnerFeeBalance(partner.address, ethers.ZeroAddress)).to.equal(expectedPartnerFee);
    });

    it("Should accumulate partner fees across multiple transactions", async function () {
      // Mint 2 NFTs with same creator
      const tokenId1 = await agentNFT.connect(admin)["mintWithRole(address,string,address)"]
        .staticCall(seller.address, "", partner.address);
      const tx1 = await agentNFT.connect(admin)["mintWithRole(address,string,address)"](seller.address, "", partner.address);
      await tx1.wait();

      const tokenId2 = await agentNFT.connect(admin)["mintWithRole(address,string,address)"]
        .staticCall(seller.address, "", partner.address);
      const tx2 = await agentNFT.connect(admin)["mintWithRole(address,string,address)"](seller.address, "", partner.address);
      await tx2.wait();

      // 验证 NFTs 已经被铸造
      expect(await agentNFT.ownerOf(tokenId1)).to.equal(seller.address);
      expect(await agentNFT.ownerOf(tokenId2)).to.equal(seller.address);

      const price = ethers.parseEther("100");

      // Transaction 1
      await agentMarket.connect(buyer).deposit(buyer.address, { value: price });
      const order1 = await createOrder(tokenId1, price, seller);
      const offer1 = await createOffer(tokenId1, price, buyer);
      await agentNFT.connect(seller).approve(await agentMarket.getAddress(), tokenId1);
      await agentMarket.connect(admin).fulfillOrder(order1, offer1, []);

      // Transaction 2
      await agentMarket.connect(buyer).deposit(buyer.address, { value: price });
      const order2 = await createOrder(tokenId2, price, seller);
      const offer2 = await createOffer(tokenId2, price, buyer);
      await agentNFT.connect(seller).approve(await agentMarket.getAddress(), tokenId2);
      await agentMarket.connect(admin).fulfillOrder(order2, offer2, []);

      // Calculate expected total fees
      const totalFee = (price * FEE_RATE) / 10000n;
      const expectedPartnerFee = (totalFee * PARTNER_FEE_RATE) / 10000n;

      expect(await agentMarket.getPartnerFeeBalance(partner.address, ethers.ZeroAddress))
        .to.equal(expectedPartnerFee * 2n);
    });

    it("Should handle 100% partner fee rate", async function () {
      // Set partner to receive 100% of fees
      await agentMarket.connect(admin).setPartnerFeeRate(partner.address, 10000n);

      const tokenId = await agentNFT.connect(admin)["mintWithRole(address,string,address)"]
        .staticCall(seller.address, "", partner.address);

      const tx = await agentNFT.connect(admin)["mintWithRole(address,string,address)"](seller.address, "", partner.address);
      await tx.wait();

      // 验证 NFT 已经被铸造
      expect(await agentNFT.ownerOf(tokenId)).to.equal(seller.address);

      const price = ethers.parseEther("100");
      await agentMarket.connect(buyer).deposit(buyer.address, { value: price });

      const order = await createOrder(tokenId, price, seller);
      const offer = await createOffer(tokenId, price, buyer);

      await agentNFT.connect(seller).approve(await agentMarket.getAddress(), tokenId);
      await agentMarket.connect(admin).fulfillOrder(order, offer, []);

      const totalFee = (price * FEE_RATE) / 10000n;

      expect(await agentMarket.getFeeBalance(ethers.ZeroAddress)).to.equal(0);
      expect(await agentMarket.getPartnerFeeBalance(partner.address, ethers.ZeroAddress)).to.equal(totalFee);
    });
  });

  describe("Partner Fee Withdrawal", function () {
    let tokenId: bigint;

    beforeEach(async function () {
      await agentMarket.connect(admin).setPartnerFeeRate(partner.address, PARTNER_FEE_RATE);

      // Create transaction to generate fees
      tokenId = await agentNFT.connect(admin)["mintWithRole(address,string,address)"]
        .staticCall(seller.address, "", partner.address);

      const tx = await agentNFT.connect(admin)["mintWithRole(address,string,address)"](seller.address, "", partner.address);
      await tx.wait();

      // 验证 NFT 已经被铸造
      expect(await agentNFT.ownerOf(tokenId)).to.equal(seller.address);

      const price = ethers.parseEther("100");
      await agentMarket.connect(buyer).deposit(buyer.address, { value: price });

      const order = await createOrder(tokenId, price, seller);
      const offer = await createOffer(tokenId, price, buyer);
      await agentNFT.connect(seller).approve(await agentMarket.getAddress(), tokenId);
      await agentMarket.connect(admin).fulfillOrder(order, offer, []);
    });

    it("Should allow partner to withdraw fees", async function () {
      const partnerBalance = await agentMarket.getPartnerFeeBalance(partner.address, ethers.ZeroAddress);
      expect(partnerBalance).to.be.gt(0);

      const partnerBalanceBefore = await ethers.provider.getBalance(partner.address);

      await expect(
        agentMarket.connect(partner).withdrawPartnerFees(ethers.ZeroAddress)
      )
        .to.emit(agentMarket, "PartnerFeesWithdrawn")
        .withArgs(partner.address, ethers.ZeroAddress, partnerBalance);

      const partnerBalanceAfter = await ethers.provider.getBalance(partner.address);
      expect(partnerBalanceAfter).to.be.gt(partnerBalanceBefore);

      // Balance should be zero after withdrawal
      expect(await agentMarket.getPartnerFeeBalance(partner.address, ethers.ZeroAddress)).to.equal(0);
    });

    it("Should revert if partner has no fees to withdraw", async function () {
      // Withdraw all fees first
      await agentMarket.connect(partner).withdrawPartnerFees(ethers.ZeroAddress);

      // Try to withdraw again
      await expect(
        agentMarket.connect(partner).withdrawPartnerFees(ethers.ZeroAddress)
      ).to.be.revertedWith("No fees to withdraw");
    });

    it("Should not affect platform fees when partner withdraws", async function () {
      const platformBalanceBefore = await agentMarket.getFeeBalance(ethers.ZeroAddress);

      await agentMarket.connect(partner).withdrawPartnerFees(ethers.ZeroAddress);

      // Platform balance should remain unchanged
      expect(await agentMarket.getFeeBalance(ethers.ZeroAddress)).to.equal(platformBalanceBefore);
    });
  });

  // Helper functions
  async function createOrder(tokenId: bigint, price: bigint, signer: SignerWithAddress) {
    const nonce = ethers.randomBytes(32);
    const expireTime = Math.floor(Date.now() / 1000) + 3600;

    const domain = {
      name: "AgentMarket",
      version: "1.0.0",
      chainId: (await ethers.provider.getNetwork()).chainId,
      verifyingContract: await agentMarket.getAddress(),
    };

    const types = {
      Order: [
        { name: "tokenId", type: "uint256" },
        { name: "expectedPrice", type: "uint256" },
        { name: "currency", type: "address" },
        { name: "expireTime", type: "uint256" },
        { name: "nonce", type: "bytes32" },
        { name: "receiver", type: "address" },
        { name: "chainId", type: "uint256" },
        { name: "verifyingContract", type: "address" },
      ],
    };

    const value = {
      tokenId,
      expectedPrice: price,
      currency: ethers.ZeroAddress,
      expireTime,
      nonce,
      receiver: ethers.ZeroAddress,
      chainId: domain.chainId,
      verifyingContract: domain.verifyingContract,
    };

    const signature = await signer.signTypedData(domain, types, value);

    return {
      tokenId,
      expectedPrice: price,
      currency: ethers.ZeroAddress,
      expireTime,
      nonce,
      signature,
      receiver: ethers.ZeroAddress,
    };
  }

  async function createOffer(tokenId: bigint, price: bigint, signer: SignerWithAddress) {
    const nonce = ethers.randomBytes(32);
    const expireTime = Math.floor(Date.now() / 1000) + 3600;

    const domain = {
      name: "AgentMarket",
      version: "1.0.0",
      chainId: (await ethers.provider.getNetwork()).chainId,
      verifyingContract: await agentMarket.getAddress(),
    };

    const types = {
      Offer: [
        { name: "tokenId", type: "uint256" },
        { name: "offeredPrice", type: "uint256" },
        { name: "expireTime", type: "uint256" },
        { name: "needProof", type: "bool" },
        { name: "nonce", type: "bytes32" },
        { name: "chainId", type: "uint256" },
        { name: "verifyingContract", type: "address" },
      ],
    };

    const value = {
      tokenId,
      offeredPrice: price,
      expireTime,
      needProof: false,
      nonce,
      chainId: domain.chainId,
      verifyingContract: domain.verifyingContract,
    };

    const signature = await signer.signTypedData(domain, types, value);

    return {
      tokenId,
      offerPrice: price,
      expireTime,
      needProof: false,
      nonce,
      signature,
    };
  }
});