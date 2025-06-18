// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IAgentMarket {
    event OrderFulfilled(
        address indexed seller, 
        address indexed buyer, 
        uint256 tokenId,
        uint256 price,
        address currency
    );
    event FeesWithdrawn(address indexed admin, address currency, uint256 amount);
    event AdminChanged(address indexed oldAdmin, address indexed newAdmin);
    event FeeRateUpdated(uint256 oldFeeRate, uint256 newFeeRate);
    event ContractPaused(address indexed admin);
    event ContractUnpaused(address indexed admin);
    
    struct Order {
        uint256 tokenId;          
        uint256 expectedPrice;    
        address currency;         
        uint256 expireTime;       
        bytes nonce;           
        bytes signature;
        // if receiver is set, the order is a directed order, can only be fulfilled by the specified receiver
        address receiver;
    }
    
    struct OrderConfirmation {       
        uint256 tokenId;          
        uint256 offerPrice;           
        uint256 expireTime;      
        bytes nonce;           
        bytes signature;         
    }
    
    function admin() external view returns (address);
    function setAdmin(address newAdmin) external;
    function withdrawFees(address currency) external;
    function getFeeBalance(address currency) external view returns (uint256);
    function setFeeRate(uint256 newFeeRate) external;
    

    function fulfillOrder(
        Order calldata order,
        OrderConfirmation calldata confirmation,
        bytes[] calldata proof
    ) external payable;
    
    function getFeeRate() external view returns (uint256);
    
    function pause() external;
    function unpause() external;
    function isPaused() external view returns (bool);
}