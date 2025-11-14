// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "./extensions/ERC7857CloneableUpgradeable.sol";
import "./interfaces/IERC7857DataVerifier.sol";
import "./Utils.sol";

contract AgentNFT is
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    ERC7857CloneableUpgradeable
{
    /// @notice The event emitted when the admin is changed
    /// @param _oldAdmin The old admin
    /// @param _newAdmin The new admin
    event AdminChanged(address indexed _oldAdmin, address indexed _newAdmin);

    event Minted(uint256 indexed _tokenId, address indexed _creator, address indexed _owner);

    /// @custom:storage-location erc7201:agent.storage.AgentNFT
    struct AgentNFTStorage {
        // Contract metadata
        string storageInfo;
        // Core components
        address admin;
    }

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    string public constant VERSION = "2.0.0";

    // keccak256(abi.encode(uint(keccak256("agent.storage.AgentNFT")) - 1)) & ~bytes32(uint(0xff))
    bytes32 private constant AGENT_NFT_STORAGE_LOCATION =
        0x4aa80aaafbe0e5fe3fe1aa97f3c1f8c65d61f96ef1aab2b448154f4e07594600;

    function _getAgentStorage() private pure returns (AgentNFTStorage storage $) {
        assembly {
            $.slot := AGENT_NFT_STORAGE_LOCATION
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        string memory storageInfo_,
        address verifierAddr,
        address admin_
    ) public virtual initializer {
        require(verifierAddr != address(0), "Zero address");
        require(admin_ != address(0), "Invalid admin address");

        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __ERC7857_init(name_, symbol_, verifierAddr);

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(ADMIN_ROLE, admin_);
        _grantRole(PAUSER_ROLE, admin_);

        AgentNFTStorage storage $ = _getAgentStorage();
        $.storageInfo = storageInfo_;
        $.admin = admin_;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(AccessControlUpgradeable, ERC7857Upgradeable, IERC165) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function setAdmin(address newAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newAdmin != address(0), "Invalid admin address");
        address oldAdmin = _getAgentStorage().admin;

        if (oldAdmin != newAdmin) {
            _getAgentStorage().admin = newAdmin;

            _grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
            _grantRole(ADMIN_ROLE, newAdmin);
            _grantRole(PAUSER_ROLE, newAdmin);

            _revokeRole(DEFAULT_ADMIN_ROLE, oldAdmin);
            _revokeRole(ADMIN_ROLE, oldAdmin);
            _revokeRole(PAUSER_ROLE, oldAdmin);

            emit AdminChanged(oldAdmin, newAdmin);
        }
    }

    // Basic getters
    function admin() public view virtual returns (address) {
        return _getAgentStorage().admin;
    }

    // Admin functions
    function updateVerifier(address newVerifier) public virtual onlyRole(ADMIN_ROLE) {
        require(newVerifier != address(0), "Zero address");
        _setVerifier(newVerifier);
    }

    function update(uint256 tokenId, IntelligentData[] calldata newDatas) public virtual {
        require(_ownerOf(tokenId) == msg.sender, "Not owner");
        require(newDatas.length > 0, "Empty data array");

        _updateData(tokenId, newDatas);
    }

    function mint(IntelligentData[] calldata iDatas, address to) public payable virtual returns (uint256 tokenId) {
        require(to != address(0), "Zero address");
        require(iDatas.length > 0, "Empty data array");

        tokenId = _incrementTokenId();
        _safeMint(to, tokenId);
        _updateData(tokenId, iDatas);

        emit Minted(tokenId, msg.sender, to);
    }

    function storageInfo() public view virtual returns (string memory) {
        return _getAgentStorage().storageInfo;
    }

    function batchAuthorizeUsage(uint256 tokenId, address[] calldata users) public virtual {
        require(users.length > 0, "Empty users array");
        require(_ownerOf(tokenId) == msg.sender, "Not owner");

        for (uint i = 0; i < users.length; i++) {
            require(users[i] != address(0), "Zero address in users");
            _authorizeUsage(tokenId, users[i]);
        }
    }

    function clearAuthorizedUsers(uint256 tokenId) public virtual {
        require(_ownerOf(tokenId) == msg.sender, "Not owner");

        _clearAuthorized(tokenId);
        emit AuthorizedUsersCleared(msg.sender, tokenId);
    }

    event AuthorizedUsersCleared(address indexed owner, uint256 indexed tokenId);
}
