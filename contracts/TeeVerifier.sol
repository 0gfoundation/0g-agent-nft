// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract TEEVerifier is Initializable, AccessControlUpgradeable, PausableUpgradeable {
    using ECDSA for bytes32;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    address public admin;
    string public constant VERSION = "1.0.0";
    address public teeOracleAddress;

    event AdminChanged(address indexed oldAdmin, address indexed newAdmin);
    event ContractPaused(address indexed admin);
    event ContractUnpaused(address indexed admin);
    event OracleAddressUpdated(address indexed oldOracleAddress, address indexed newOracleAddress);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _admin, address _teeOracleAddress) public initializer {
        require(_admin != address(0), "Invalid admin address");
        require(_teeOracleAddress != address(0), "Invalid tee oracle address");

        __AccessControl_init();
        __Pausable_init();

        admin = _admin;
        teeOracleAddress = _teeOracleAddress;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
    }

    function setAdmin(address newAdmin) public onlyRole(DEFAULT_ADMIN_ROLE) {
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

    function verifyTEESignature(bytes32 dataHash, bytes calldata signature) external view returns (bool) {
        require(signature.length == 65, "Invalid signature length");

        address signer = dataHash.recover(signature);
        return signer == teeOracleAddress;
    }

    function updateOracleAddress(address newOracleAddress) public onlyRole(ADMIN_ROLE) {
        require(newOracleAddress != address(0), "Invalid tee oracle address");
        address oldOracleAddress = teeOracleAddress;
        teeOracleAddress = newOracleAddress;

        emit OracleAddressUpdated(oldOracleAddress, newOracleAddress);
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
        emit ContractPaused(msg.sender);
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
        emit ContractUnpaused(msg.sender);
    }

    function isPaused() public view returns (bool) {
        return paused();
    }
}
