// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {IERC7857} from "./interfaces/IERC7857.sol";
import {IERC7857Metadata} from "./interfaces/IERC7857Metadata.sol";
import {IERC7857DataVerifier, PreimageProofOutput, TransferValidityProofOutput} from "./interfaces/IERC7857DataVerifier.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract AgentNFT is
    AccessControlEnumerableUpgradeable,
    IERC7857,
    IERC7857Metadata
{
    event Approval(
        address indexed _from,
        address indexed _to,
        uint256 indexed _tokenId
    );
    event ApprovalForAll(
        address indexed _owner,
        address indexed _operator,
        bool _approved
    );

    /// @custom:storage-location erc7201:agent.storage.AgentNFT
    struct AgentNFTStorage {
        // Token data
        mapping(uint256 => TokenData) tokens;
        mapping(address owner => mapping(address operator => bool)) operatorApprovals;
        mapping(address user => address realAccessor) delegateAccess;
        uint256 nextTokenId;
        // Contract metadata
        string name;
        string symbol;
        string chainURL;
        string indexerURL;
        // Core components
        IERC7857DataVerifier verifier;
    }

    struct TokenData {
        address owner;
        string[] dataDescriptions;
        bytes32[] dataHashes;
        address[] authorizedUsers;
        address approvedUser;
    }

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    string public constant VERSION = "2.0.0";

    // keccak256(abi.encode(uint(keccak256("agent.storage.AgentNFT")) - 1)) & ~bytes32(uint(0xff))
    bytes32 private constant AGENT_NFT_STORAGE_LOCATION =
        0x4aa80aaafbe0e5fe3fe1aa97f3c1f8c65d61f96ef1aab2b448154f4e07594600;

    function _getAgentStorage()
        private
        pure
        returns (AgentNFTStorage storage $)
    {
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
        address verifierAddr,
        string memory chainURL_,
        string memory indexerURL_,
        address admin_
    ) public virtual initializer {
        require(verifierAddr != address(0), "Zero address");

        __AccessControlEnumerable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(ADMIN_ROLE, admin_);
        _grantRole(PAUSER_ROLE, admin_);

        AgentNFTStorage storage $ = _getAgentStorage();
        $.name = name_;
        $.symbol = symbol_;
        $.chainURL = chainURL_;
        $.indexerURL = indexerURL_;
        $.verifier = IERC7857DataVerifier(verifierAddr);
    }

    // Basic getters
    function name() public view virtual returns (string memory) {
        return _getAgentStorage().name;
    }

    function symbol() public view virtual returns (string memory) {
        return _getAgentStorage().symbol;
    }

    function verifier() public view virtual returns (IERC7857DataVerifier) {
        return _getAgentStorage().verifier;
    }

    // Admin functions
    function updateVerifier(
        address newVerifier
    ) public virtual onlyRole(ADMIN_ROLE) {
        require(newVerifier != address(0), "Zero address");
        _getAgentStorage().verifier = IERC7857DataVerifier(newVerifier);
    }

    function updateURLS(
        string memory newChainURL,
        string memory newIndexerURL
    ) public virtual onlyRole(ADMIN_ROLE) {
        AgentNFTStorage storage $ = _getAgentStorage();
        $.chainURL = newChainURL;
        $.indexerURL = newIndexerURL;
    }

    function update(uint256 tokenId, bytes[] calldata proofs) public virtual {
        AgentNFTStorage storage $ = _getAgentStorage();
        TokenData storage token = $.tokens[tokenId];
        require(token.owner == msg.sender, "Not owner");

        PreimageProofOutput[] memory proofOutput = $.verifier.verifyPreimage(
            proofs
        );
        bytes32[] memory newDataHashes = new bytes32[](proofOutput.length);

        for (uint i = 0; i < proofOutput.length; i++) {
            require(
                proofOutput[i].isValid,
                string(
                    abi.encodePacked(
                        "Invalid preimage proof at index ",
                        i,
                        " with data hash ",
                        proofOutput[i].dataHash
                    )
                )
            );
            newDataHashes[i] = proofOutput[i].dataHash;
        }

        bytes32[] memory oldDataHashes = token.dataHashes;
        token.dataHashes = newDataHashes;

        emit Updated(tokenId, oldDataHashes, newDataHashes);
    }

    function mint(
        bytes[] calldata proofs,
        string[] calldata dataDescriptions,
        address to
    ) public payable virtual returns (uint256 tokenId) {
        AgentNFTStorage storage $ = _getAgentStorage();

        require(
            dataDescriptions.length == proofs.length,
            "Descriptions and proofs length mismatch"
        );

        if (to == address(0)) {
            to = msg.sender;
        }

        PreimageProofOutput[] memory proofOutput = $.verifier.verifyPreimage(
            proofs
        );
        bytes32[] memory dataHashes = new bytes32[](proofOutput.length);

        for (uint i = 0; i < proofOutput.length; i++) {
            require(
                proofOutput[i].isValid,
                string(
                    abi.encodePacked(
                        "Invalid preimage proof at index ",
                        i,
                        " with data hash ",
                        proofOutput[i].dataHash
                    )
                )
            );
            dataHashes[i] = proofOutput[i].dataHash;
        }

        tokenId = $.nextTokenId++;
        $.tokens[tokenId] = TokenData({
            owner: to,
            dataHashes: dataHashes,
            dataDescriptions: dataDescriptions,
            authorizedUsers: new address[](0),
            approvedUser: address(0)
        });

        emit Minted(tokenId, msg.sender, to, dataHashes, dataDescriptions);
    }

    function transfer(
        address to,
        uint256 tokenId,
        bytes[] calldata proofs
    ) public virtual {
        AgentNFTStorage storage $ = _getAgentStorage();
        require(to != address(0), "Zero address");
        require($.tokens[tokenId].owner == msg.sender, "Not owner");

        TransferValidityProofOutput[] memory proofOutput = $
            .verifier
            .verifyTransferValidity(proofs);
        bytes16[] memory sealedKeys = new bytes16[](proofOutput.length);
        bytes32[] memory newDataHashes = new bytes32[](proofOutput.length);
        bool isPrivate = (uint8(proofs[0][0]) & 0x40) != 0;

        for (uint i = 0; i < proofOutput.length; i++) {
            require(proofOutput[i].isValid, "Invalid transfer validity proof");
            require(
                proofOutput[i].newDataHash ==
                    $.tokens[tokenId].dataHashes[i],
                "New data hash mismatch"
            );
            if (isPrivate) {
                require(proofOutput[i].receiver == to, "Receiver mismatch");
            }
            require(
                proofOutput[i].realAccessor == $.delegateAccess[to] ||
                    proofOutput[i].realAccessor == to,
                "Accessor mismatch"
            );
            sealedKeys[i] = proofOutput[i].sealedKey;
            newDataHashes[i] = proofOutput[i].newDataHash;
        }

        $.tokens[tokenId].owner = to;
        $.tokens[tokenId].dataHashes = newDataHashes;

        emit Transferred(tokenId, msg.sender, to);
        emit PublishedSealedKey(to, tokenId, sealedKeys);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes[] calldata proofs
    ) public virtual {
        AgentNFTStorage storage $ = _getAgentStorage();
        require(to != address(0), "Zero address");
        require($.tokens[tokenId].owner == from, "Not owner");
        require(
            $.tokens[tokenId].approvedUser == msg.sender ||
                $.tokens[tokenId].owner == msg.sender ||
                $.operatorApprovals[from][msg.sender],
            "Not approved"
        );

        bool isPrivate = (uint8(proofs[0][0]) & 0x40) != 0;

        TransferValidityProofOutput[] memory proofOutput = $
            .verifier
            .verifyTransferValidity(proofs);
        bytes16[] memory sealedKeys = new bytes16[](proofOutput.length);
        bytes32[] memory newDataHashes = new bytes32[](proofOutput.length);


        for (uint i = 0; i < proofOutput.length; i++) {
            require(proofOutput[i].isValid, "Invalid transfer validity proof");
            require(
                proofOutput[i].newDataHash == $.tokens[tokenId].dataHashes[i],
                "New data hash mismatch"
            );
            if (isPrivate) {
                require(proofOutput[i].receiver == to, "Receiver mismatch");
            }
            require(
                proofOutput[i].realAccessor == $.delegateAccess[to] ||
                    proofOutput[i].realAccessor == to,
                "Accessor mismatch"
            );
            sealedKeys[i] = proofOutput[i].sealedKey;
            newDataHashes[i] = proofOutput[i].newDataHash;
        }

        $.tokens[tokenId].owner = to;
        $.tokens[tokenId].dataHashes = newDataHashes;

        emit Transferred(tokenId, msg.sender, to);
        emit PublishedSealedKey(to, tokenId, sealedKeys);
    }

    function clone(
        address to,
        uint256 tokenId,
        bytes[] calldata proofs
    ) public virtual returns (uint256) {
        AgentNFTStorage storage $ = _getAgentStorage();
        require(to != address(0), "Zero address");
        require($.tokens[tokenId].owner == msg.sender, "Not owner");

        bool isPrivate = (uint8(proofs[0][0]) & 0x40) != 0;

        TransferValidityProofOutput[] memory proofOutput = $
            .verifier
            .verifyTransferValidity(proofs);
        bytes32[] memory newDataHashes = new bytes32[](proofOutput.length);
        bytes16[] memory sealedKeys = new bytes16[](proofOutput.length);

        for (uint i = 0; i < proofOutput.length; i++) {
            require(proofOutput[i].isValid, "Invalid transfer validity proof");
            require(
                proofOutput[i].oldDataHash ==
                    $.tokens[tokenId].dataHashes[i],
                "Old data hash mismatch"
            );
            if (isPrivate) {
                require(proofOutput[i].receiver == to, "Receiver mismatch");
            }
            require(
                proofOutput[i].realAccessor == $.delegateAccess[to] ||
                    proofOutput[i].realAccessor == to,
                "Accessor mismatch"
            );
            sealedKeys[i] = proofOutput[i].sealedKey;
            newDataHashes[i] = proofOutput[i].newDataHash;
        }

        uint256 newTokenId = $.nextTokenId++;
        $.tokens[newTokenId] = TokenData({
            owner: to,
            dataHashes: newDataHashes,
            dataDescriptions: $.tokens[tokenId].dataDescriptions,
            authorizedUsers: new address[](0),
            approvedUser: address(0)
        });

        emit Cloned(tokenId, newTokenId, msg.sender, to);
        emit PublishedSealedKey(to, newTokenId, sealedKeys);
        return newTokenId;
    }

    function cloneFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes[] calldata proofs
    ) public virtual returns (uint256) {
        AgentNFTStorage storage $ = _getAgentStorage();
        require(to != address(0), "Zero address");
        require($.tokens[tokenId].owner == from, "Not owner");

        require(
            $.tokens[tokenId].approvedUser == msg.sender ||
                $.tokens[tokenId].owner == msg.sender ||
                $.operatorApprovals[from][msg.sender],
            "Not approved"
        );

        TransferValidityProofOutput[] memory proofOutput = $
            .verifier
            .verifyTransferValidity(proofs);
        bytes32[] memory newDataHashes = new bytes32[](proofOutput.length);
        bytes16[] memory sealedKeys = new bytes16[](proofOutput.length);

        bool isPrivate = (uint8(proofs[0][0]) & 0x40) != 0;

        for (uint i = 0; i < proofOutput.length; i++) {
            require(proofOutput[i].isValid, "Invalid transfer validity proof");
            require(
                proofOutput[i].oldDataHash ==
                    $.tokens[tokenId].dataHashes[i],
                "Old data hash mismatch"
            );
            if (isPrivate) {
                require(proofOutput[i].receiver == to, "Receiver mismatch");
            }
            require(
                proofOutput[i].realAccessor == $.delegateAccess[to] ||
                    proofOutput[i].realAccessor == to,
                "Accessor mismatch"
            );

            sealedKeys[i] = proofOutput[i].sealedKey;
            newDataHashes[i] = proofOutput[i].newDataHash;
        }

        uint256 newTokenId = $.nextTokenId++;
        $.tokens[newTokenId] = TokenData({
            owner: to,
            dataHashes: newDataHashes,
            dataDescriptions: $.tokens[tokenId].dataDescriptions,
            authorizedUsers: new address[](0),
            approvedUser: address(0)
        });

        emit Cloned(tokenId, newTokenId, msg.sender, to);
        emit PublishedSealedKey(to, newTokenId, sealedKeys);
        return newTokenId;
    }

    function authorizeUsage(uint256 tokenId, address to) public virtual {
        AgentNFTStorage storage $ = _getAgentStorage();
        require($.tokens[tokenId].owner == msg.sender, "Not owner");
        $.tokens[tokenId].authorizedUsers.push(to);
        emit Authorization(msg.sender, to, tokenId);
    }

    function ownerOf(uint256 tokenId) public view virtual returns (address) {
        AgentNFTStorage storage $ = _getAgentStorage();
        TokenData storage token = $.tokens[tokenId];
        require(token.owner != address(0), "Token not exist");
        return token.owner;
    }

    function authorizedUsersOf(
        uint256 tokenId
    ) public view virtual returns (address[] memory) {
        AgentNFTStorage storage $ = _getAgentStorage();
        TokenData storage token = $.tokens[tokenId];
        require(token.owner != address(0), "Token not exist");
        return token.authorizedUsers;
    }

    function tokenURI(
        uint256 tokenId
    ) public view virtual returns (string memory) {
        AgentNFTStorage storage $ = _getAgentStorage();
        require(_exists(tokenId), "Token does not exist");

        return
            string(
                abi.encodePacked(
                    '{"chainURL":"',
                    $.chainURL,
                    '","indexerURL":"',
                    $.indexerURL,
                    '"}'
                )
            );
    }

    function _exists(uint256 tokenId) internal view returns (bool) {
        return _getAgentStorage().tokens[tokenId].owner != address(0);
    }

    function dataHashesOf(
        uint256 tokenId
    ) public view virtual returns (bytes32[] memory) {
        AgentNFTStorage storage $ = _getAgentStorage();
        TokenData storage token = $.tokens[tokenId];
        require(token.owner != address(0), "Token not exist");
        return token.dataHashes;
    }

    function dataDescriptionsOf(
        uint256 tokenId
    ) public view virtual returns (string[] memory) {
        AgentNFTStorage storage $ = _getAgentStorage();
        TokenData storage token = $.tokens[tokenId];
        require(token.owner != address(0), "Token not exist");
        return token.dataDescriptions;
    }

    function approve(address to, uint256 tokenId) public virtual {
        AgentNFTStorage storage $ = _getAgentStorage();
        require($.tokens[tokenId].owner == msg.sender, "Not owner");
        $.tokens[tokenId].approvedUser = to;
        emit Approval(msg.sender, to, tokenId);
    }

    function setApprovalForAll(address to, bool approved) public virtual {
        AgentNFTStorage storage $ = _getAgentStorage();
        $.operatorApprovals[msg.sender][to] = approved;
        emit ApprovalForAll(msg.sender, to, approved);
    }

    function getApproved(
        uint256 tokenId
    ) public view virtual returns (address operator) {
        AgentNFTStorage storage $ = _getAgentStorage();
        return $.tokens[tokenId].approvedUser;
    }

    function isApprovedForAll(
        address owner,
        address operator
    ) public view virtual returns (bool) {
        AgentNFTStorage storage $ = _getAgentStorage();
        return $.operatorApprovals[owner][operator];
    }

    function delegateAccess(address realAccessor) public virtual {
        AgentNFTStorage storage $ = _getAgentStorage();
        $.delegateAccess[msg.sender] = realAccessor;
    }

    function getDelegateAccess(address user) public view virtual returns (address) {
        AgentNFTStorage storage $ = _getAgentStorage();
        return $.delegateAccess[user];
    }
}
