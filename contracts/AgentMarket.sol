// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IAgentMarket.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "./AgentNFT.sol";
import "./Utils.sol";

contract AgentMarket is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    IAgentMarket
{
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    address public override admin;
    uint256 private feeRate;
    uint256 public constant MAX_FEE_RATE = 1000;
    // 0.1 0G: 100000000000000000
    uint256 private mintFee;
    // 0 0G: 0
    uint256 private discountMintFee;

    address public agentNFT;

    mapping(address => uint256) public feeBalances;
    mapping(address => uint256) public balances;
    mapping(uint256 => bool) public usedOrders;
    mapping(uint256 => bool) public usedOffers;

    string public constant VERSION = "1.0.0";

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _agentNFT,
        uint256 _initialFeeRate,
        address _admin,
        uint256 _initialMintFee,
        uint256 _initialDiscountMintFee
    ) external initializer {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        require(_admin != address(0), "Invalid admin address");
        require(_agentNFT != address(0), "Invalid AgentNFT address");
        require(_initialFeeRate <= MAX_FEE_RATE, "Fee rate too high");

        admin = _admin;
        agentNFT = _agentNFT;
        feeRate = _initialFeeRate;
        mintFee = _initialMintFee;
        discountMintFee = _initialDiscountMintFee;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
    }

    function setAdmin(address newAdmin) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newAdmin != address(0), "Invalid admin address");
        address oldAdmin = admin;

        if (oldAdmin != newAdmin) {
            admin = newAdmin;

            _grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
            _grantRole(ADMIN_ROLE, newAdmin);
            _grantRole(PAUSER_ROLE, newAdmin);

            _revokeRole(DEFAULT_ADMIN_ROLE, oldAdmin);
            _revokeRole(ADMIN_ROLE, oldAdmin);
            _revokeRole(PAUSER_ROLE, oldAdmin);

            emit AdminChanged(oldAdmin, newAdmin);
        }
    }

    function setFeeRate(uint256 newFeeRate) external override onlyRole(ADMIN_ROLE) {
        require(newFeeRate <= MAX_FEE_RATE, "Fee rate too high");
        uint256 oldFeeRate = feeRate;
        feeRate = newFeeRate;
        emit FeeRateUpdated(oldFeeRate, newFeeRate);
    }

    event AgentNFTUpdated(address oldAgentNFT, address newAgentNFT);

    function setAgentNFT(address _agentNFT) external onlyRole(ADMIN_ROLE) {
        require(_agentNFT != address(0), "Invalid AgentNFT address");
        address oldAgentNFT = agentNFT;
        agentNFT = _agentNFT;
        emit AgentNFTUpdated(oldAgentNFT, _agentNFT);
    }

    function withdrawFees(address currency) external override onlyRole(ADMIN_ROLE) {
        uint256 amount = feeBalances[currency];
        require(amount > 0, "No fees to withdraw");

        if (currency == address(0)) {
            // withdraw 0G
            _safeTransferNative(admin, amount);
        } else {
            // withdraw ERC20 - only update balance after successful transfer
            IERC20(currency).safeTransfer(admin, amount);
        }
        feeBalances[currency] = 0;

        emit FeesWithdrawn(admin, currency, amount);
    }

    // core transaction function
    function fulfillOrder(
        Order calldata order,
        Offer calldata offer,
        TransferValidityProof[] calldata proofs
    ) external payable override nonReentrant whenNotPaused {
        // 1. verify order and offer:
        // 1.1 verify signature
        // 1.2 verify expiration
        // 1.3 verify nonce is not used
        // 1.4 verify NFT owner is seller
        // 1.5 verify offerPrice >= expectedPrice
        address seller = _validateOrder(order);
        address buyer = _validateOffer(offer, order);

        // 2. transfer iNFT
        if (proofs.length > 0) {
            AgentNFT(agentNFT).iTransferFrom(seller, buyer, order.tokenId, proofs);
        } else {
            AgentNFT(agentNFT).transferFrom(seller, buyer, order.tokenId);
        }

        // 3. transfer erc20 token or A0GI
        if (offer.offerPrice > 0) {
            _handlePayment(offer.offerPrice, order.currency, buyer, seller);
        }

        if (order.receiver != address(0)) {
            require(buyer == order.receiver, "Receiver mismatch");
        }
        // 4. mark order and offer as used
        usedOrders[uint256(order.nonce)] = true;
        usedOffers[uint256(offer.nonce)] = true;

        emit OrderFulfilled(seller, buyer, order.tokenId, offer.offerPrice, order.currency);
    }

    function deposit(address account) external payable {
        require(msg.value > 0, "Must send ETH");
        require(account != address(0), "Invalid address");
        require(!paused(), "Contract is paused");
        balances[account] += msg.value;
        emit Deposit(account, balances[account]);
    }

    function withdraw(address account, uint256 amount) external {
        require(msg.sender == account || msg.sender == admin, "Only the account or admin can withdraw");
        require(balances[account] >= amount, "Insufficient balance");
        require(account != address(0), "Invalid address");
        require(!paused(), "Contract is paused");
        balances[account] -= amount;
        _safeTransferNative(account, amount);
        emit Withdraw(account, amount);
    }

    function getBalance(address account) external view returns (uint256) {
        return balances[account];
    }

    function _validateOrder(Order calldata order) internal view returns (address) {
        // 1.1 verify expiration
        require(block.timestamp <= order.expireTime, "Order expired");
        // 1.2 verify price
        require(order.expectedPrice >= 0, "Invalid price");
        // 1.3 verify order nonce is not used
        address seller = _verifyOrderSignature(order);
        require(!usedOrders[uint256(order.nonce)], "Order already used");
        // 1.4 verify NFT owner is seller
        address tokenOwner = AgentNFT(agentNFT).ownerOf(order.tokenId);
        require(tokenOwner == seller, "NFT owner mismatch");

        return seller;
    }

    function _validateOffer(Offer calldata offer, Order calldata order) internal view returns (address) {
        require(block.timestamp <= offer.expireTime, "Offer expired");
        require(offer.offerPrice >= order.expectedPrice, "Price too low");
        require(offer.tokenId == order.tokenId, "TokenId mismatch");

        address buyer = _verifyOfferSignature(offer);
        require(!usedOffers[uint256(offer.nonce)], "Offer already used");

        if (order.receiver != address(0)) {
            require(buyer == order.receiver, "Receiver mismatch");
        }

        return buyer;
    }

    function _verifyOrderSignature(Order calldata order) internal view returns (address) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Order(uint256 tokenId,uint256 expectedPrice,address currency,uint256 expireTime,bytes32 nonce,address receiver,uint256 chainId,address verifyingContract)"
                ),
                order.tokenId,
                order.expectedPrice,
                order.currency,
                order.expireTime,
                order.nonce,
                order.receiver,
                block.chainid,
                address(this)
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparatorV4(), structHash));

        return digest.recover(order.signature);
    }

    function _verifyOfferSignature(Offer calldata offer) internal view returns (address) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Offer(uint256 tokenId,uint256 offeredPrice,uint256 expireTime,bytes32 nonce,uint256 chainId,address verifyingContract)"
                ),
                offer.tokenId,
                offer.offerPrice,
                offer.expireTime,
                offer.nonce,
                block.chainid,
                address(this)
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparatorV4(), structHash));

        return digest.recover(offer.signature);
    }

    function _domainSeparatorV4() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256(bytes("AgentMarket")),
                    keccak256(bytes(VERSION)),
                    block.chainid,
                    address(this)
                )
            );
    }

    function _handlePayment(uint256 offerPrice, address currency, address buyer, address seller) internal {
        uint256 totalAmount = offerPrice;
        uint256 fee = (totalAmount * feeRate) / 10000;
        uint256 sellerAmount = totalAmount - fee;

        IERC20 token = IERC20(currency);
        // native token
        if (currency == address(0)) {
            require(balances[buyer] >= totalAmount, "Insufficient balance");
            _safeTransferNative(seller, sellerAmount);
            balances[buyer] -= totalAmount;
        } else {
            token.safeTransferFrom(buyer, seller, sellerAmount);
            token.safeTransferFrom(buyer, address(this), fee);
        }
        feeBalances[currency] += fee;
    }

    function getFeeRate() external view override returns (uint256) {
        return feeRate;
    }

    function getFeeBalance(address currency) external view override returns (uint256) {
        return feeBalances[currency];
    }

    function _safeTransferNative(address to, uint256 amount) internal {
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");

        (bool success, ) = payable(to).call{value: amount}("");
        require(success, "Native token transfer failed");
    }

    event MintFeeUpdated(uint256 mintFee);

    // for paid mint
    function setMintFee(uint256 newMintFee) external onlyRole(ADMIN_ROLE) {
        mintFee = newMintFee;
        emit MintFeeUpdated(mintFee);
    }

    event DiscountMintFeeUpdated(uint256 discountMintFee);

    function setDiscountMintFee(uint256 newDiscountMintFee) external onlyRole(ADMIN_ROLE) {
        discountMintFee = newDiscountMintFee;
        emit DiscountMintFeeUpdated(discountMintFee);
    }

    function getMintFee() external view returns (uint256) {
        return mintFee;
    }

    function getDiscountMintFee() external view returns (uint256) {
        return discountMintFee;
    }

    event PaidMinted(uint256 indexed tokenId, address indexed from, address indexed to, uint256 mintFee);

    function paidMint(IntelligentData[] calldata iDatas, address to, bool isDiscount) external onlyRole(ADMIN_ROLE) {
        uint256 requiredFee = isDiscount ? discountMintFee : mintFee;
        require(balances[to] >= requiredFee, "Insufficient balance for mint fee");
        require(to != address(0), "Invalid recipient");
        require(!paused(), "Contract is paused");
        balances[to] -= requiredFee;
        feeBalances[address(0)] += requiredFee;
        uint256 tokenId = AgentNFT(agentNFT).mint(iDatas, to);
        emit PaidMinted(tokenId, msg.sender, to, requiredFee);
    }

    function pause() external override onlyRole(PAUSER_ROLE) {
        _pause();
        emit ContractPaused(msg.sender);
    }

    function unpause() external override onlyRole(PAUSER_ROLE) {
        _unpause();
        emit ContractUnpaused(msg.sender);
    }

    function isPaused() external view override returns (bool) {
        return paused();
    }

    uint256[50] private __gap;
}
