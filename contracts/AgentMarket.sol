// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IAgentMarket.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "./AgentNFT.sol";

contract AgentMarket is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    IAgentMarket
{
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    address public override admin;
    uint256 private _feeRate;
    uint256 public constant MAX_FEE_RATE = 1000;

    address public agentNFT;

    mapping(address => uint256) public feeBalances;
    mapping(uint256 => bool) public usedOrders;
    mapping(uint256 => bool) public usedConfirmations;

    string public constant VERSION = "1.0.0";

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _agentNFT,
        uint256 _initialFeeRate,
        address _admin
    ) external initializer {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        require(_admin != address(0), "Invalid admin address");
        require(_agentNFT != address(0), "Invalid AgentNFT address");
        require(_initialFeeRate <= MAX_FEE_RATE, "Fee rate too high");

        admin = _admin;
        agentNFT = _agentNFT;
        _feeRate = _initialFeeRate;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
    }

    function setAdmin(address newAdmin) external override onlyRole(ADMIN_ROLE) {
        require(newAdmin != address(0), "Invalid admin address");
        address oldAdmin = admin;
        admin = newAdmin;

        _grantRole(ADMIN_ROLE, newAdmin);
        _grantRole(PAUSER_ROLE, newAdmin);

        if (oldAdmin != newAdmin) {
            _revokeRole(ADMIN_ROLE, oldAdmin);
            _revokeRole(PAUSER_ROLE, oldAdmin);
        }

        emit AdminChanged(oldAdmin, newAdmin);
    }

    function setFeeRate(
        uint256 newFeeRate
    ) external override onlyRole(ADMIN_ROLE) {
        require(newFeeRate <= MAX_FEE_RATE, "Fee rate too high");
        uint256 oldFeeRate = _feeRate;
        _feeRate = newFeeRate;
        emit FeeRateUpdated(oldFeeRate, newFeeRate);
    }

    function setAgentNFT(address _agentNFT) external onlyRole(ADMIN_ROLE) {
        require(_agentNFT != address(0), "Invalid AgentNFT address");
        agentNFT = _agentNFT;
    }

    function withdrawFees(
        address currency
    ) external override onlyRole(ADMIN_ROLE) {
        uint256 amount = feeBalances[currency];
        require(amount > 0, "No fees to withdraw");

        feeBalances[currency] = 0;

        if (currency == address(0)) {
            // withdraw ETH
            payable(admin).transfer(amount);
        } else {
            // withdraw ERC20
            IERC20(currency).transfer(admin, amount);
        }

        emit FeesWithdrawn(admin, currency, amount);
    }

    // core transaction function
    function fulfillOrder(
        Order calldata order,
        OrderConfirmation calldata confirmation,
        bytes[] calldata proofs
    ) external payable override nonReentrant whenNotPaused {
        // 1. verify order and confirmation:
        // 1.1 verify signature
        // 1.2 verify expiration
        // 1.3 verify nonce is not used
        // 1.4 verify NFT owner is seller
        // 1.5 verify offerPrice >= expectedPrice
        address seller = _validateOrder(order);
        address buyer = _validateConfirmation(confirmation, order);

        // 2. transfer iNFT
        AgentNFT(agentNFT).transferFrom(seller, buyer, order.tokenId, proofs);

        // 3. transfer erc20 token
        if (confirmation.offerPrice > 0) {
            _handlePayment(
                confirmation.offerPrice,
                order.currency,
                buyer,
                seller
            );
        }

        if (order.receiver != address(0)) {
            require(buyer == order.receiver, "Receiver mismatch");
        }
        // 4. mark order and confirmation as used
        usedOrders[uint256(keccak256(order.nonce))] = true;
        usedConfirmations[uint256(keccak256(confirmation.nonce))] = true;

        emit OrderFulfilled(
            seller,
            buyer,
            order.tokenId,
            confirmation.offerPrice,
            order.currency
        );
    }

    function _validateOrder(
        Order calldata order
    ) internal view returns (address) {
        // 1.1 verify expiration
        require(block.timestamp <= order.expireTime, "Order expired");
        // 1.2 verify price
        require(order.expectedPrice >= 0, "Invalid price");
        // 1.3 verify order nonce is not used
        address seller = _verifyOrderSignature(order);
        require(
            !usedOrders[uint256(keccak256(order.nonce))],
            "Order already used"
        );
        // 1.4 verify NFT owner is seller
        address tokenOwner = AgentNFT(agentNFT).ownerOf(order.tokenId);
        require(tokenOwner == seller, "NFT owner mismatch");

        return seller;
    }

    function _validateConfirmation(
        OrderConfirmation calldata confirmation,
        Order calldata order
    ) internal view returns (address) {
        require(
            block.timestamp <= confirmation.expireTime,
            "Confirmation expired"
        );
        require(
            confirmation.offerPrice >= order.expectedPrice,
            "Price too low"
        );
        require(confirmation.tokenId == order.tokenId, "TokenId mismatch");

        address buyer = _verifyConfirmationSignature(confirmation);
        require(
            !usedConfirmations[uint256(keccak256(confirmation.nonce))],
            "Confirmation already used"
        );

        return buyer;
    }

    function _verifyOrderSignature(
        Order calldata order
    ) internal pure returns (address) {
        bytes32 orderHashHex = keccak256(
            abi.encodePacked(
                order.tokenId,
                order.expectedPrice,
                order.currency,
                order.expireTime,
                order.nonce,
                order.receiver
            )
        );

        string memory message = Strings.toHexString(uint256(orderHashHex), 32);
        bytes32 ethSignedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n66", message)
        );

        address seller = ethSignedHash.recover(order.signature);
        return seller;
    }

    function _verifyConfirmationSignature(
        OrderConfirmation calldata confirmation
    ) internal pure returns (address) {
        bytes32 confirmationHashHex = keccak256(
            abi.encodePacked(
                confirmation.tokenId,
                confirmation.offerPrice,
                confirmation.expireTime,
                confirmation.nonce
            )
        );

        string memory message = Strings.toHexString(
            uint256(confirmationHashHex),
            32
        );
        bytes32 ethSignedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n66", message)
        );

        address buyer = ethSignedHash.recover(confirmation.signature);
        return buyer;
    }

    function _handlePayment(
        uint256 offerPrice,
        address currency,
        address buyer,
        address seller
    ) internal {
        uint256 totalAmount = offerPrice;
        uint256 fee = (totalAmount * _feeRate) / 10000;
        uint256 sellerAmount = totalAmount - fee;

        IERC20 token = IERC20(currency);

        token.transferFrom(buyer, seller, sellerAmount);

        token.transferFrom(buyer, address(this), fee);
        feeBalances[currency] += fee;
    }

    function getFeeRate() external view override returns (uint256) {
        return _feeRate;
    }

    function getFeeBalance(
        address currency
    ) external view override returns (uint256) {
        return feeBalances[currency];
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
