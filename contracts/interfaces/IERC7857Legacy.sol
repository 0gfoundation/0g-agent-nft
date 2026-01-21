// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {IERC7857DataVerifier, TransferValidityProof} from "./IERC7857DataVerifier.sol";
import {IERC7857Metadata} from "./IERC7857Metadata.sol";

interface IERC7857Legacy {
    /// @notice The event emitted when an address is approved to transfer a token
    /// @param _from The address that is approving
    /// @param _to The address that is being approved
    /// @param _tokenId The token identifier
    event Approval(address indexed _from, address indexed _to, uint256 indexed _tokenId);

    /// @notice The event emitted when an address is approved for all
    /// @param _owner The owner
    /// @param _operator The operator
    /// @param _approved The approval
    event ApprovalForAll(address indexed _owner, address indexed _operator, bool _approved);

    /// @notice The event emitted when an address is authorized to use a token
    /// @param _from The address that is authorizing
    /// @param _to The address that is being authorized
    /// @param _tokenId The token identifier
    event Authorization(address indexed _from, address indexed _to, uint256 indexed _tokenId);

    /// @notice The event emitted when an address is revoked from using a token
    /// @param _from The address that is revoking
    /// @param _to The address that is being revoked
    /// @param _tokenId The token identifier
    event AuthorizationRevoked(address indexed _from, address indexed _to, uint256 indexed _tokenId);

    /// @notice The event emitted when a token is transferred
    /// @param _tokenId The token identifier
    /// @param _from The address that is transferring
    /// @param _to The address that is receiving
    event Transferred(uint256 _tokenId, address indexed _from, address indexed _to);

    /// @notice The event emitted when a token is cloned
    /// @param _tokenId The token identifier
    /// @param _newTokenId The new token identifier
    /// @param _from The address that is cloning
    /// @param _to The address that is receiving
    event Cloned(uint256 indexed _tokenId, uint256 indexed _newTokenId, address _from, address _to);

    /// @notice The event emitted when a sealed key is published
    /// @param _to The address that is receiving
    /// @param _tokenId The token identifier
    /// @param _sealedKeys The sealed keys
    event PublishedSealedKey(address indexed _to, uint256 indexed _tokenId, bytes[] _sealedKeys);

    /// @notice The event emitted when a user is delegated to an assistant
    /// @param _user The user
    /// @param _assistant The assistant
    event DelegateAccess(address indexed _user, address indexed _assistant);

    /// @notice The event emitted when the admin is changed
    /// @param _oldAdmin The old admin
    /// @param _newAdmin The new admin
    event AdminChanged(address indexed _oldAdmin, address indexed _newAdmin);

    /// @notice The verifier interface that this NFT uses
    /// @return The address of the verifier contract
    function verifier() external view returns (IERC7857DataVerifier);

    /// @notice Get the admin of the NFT
    /// @return The address of the admin
    function admin() external view returns (address);

    /// @notice Set the admin of the NFT
    /// @param newAdmin The new admin
    function setAdmin(address newAdmin) external;

    /// @notice Transfer data with ownership
    /// @param _to Address to transfer data to
    /// @param _tokenId The token to transfer data for
    /// @param _proofs Proofs of data available for _to
    function iTransfer(address _to, uint256 _tokenId, TransferValidityProof[] calldata _proofs) external;

    /// @notice Clone data
    /// @param _to Address to clone data to
    /// @param _tokenId The token to clone data for
    /// @param _proofs Proofs of data available for _to
    /// @return _newTokenId The ID of the newly cloned token
    function iClone(
        address _to,
        uint256 _tokenId,
        TransferValidityProof[] calldata _proofs
    ) external returns (uint256 _newTokenId);

    /// @notice Add authorized user to group
    /// @param _tokenId The token to add to group
    function authorizeUsage(uint256 _tokenId, address _user) external;

    /// @notice Revoke authorization from a user
    /// @param _tokenId The token to revoke authorization from
    /// @param _user The user to revoke authorization from
    function revokeAuthorization(uint256 _tokenId, address _user) external;

    /// @notice Approve an address to transfer a token
    /// @param _to The address to approve
    /// @param _tokenId The token identifier
    function approve(address _to, uint256 _tokenId) external;

    /// @notice Set approval for all
    /// @param _operator The operator
    /// @param _approved The approval
    function setApprovalForAll(address _operator, bool _approved) external;

    /// @notice Delegate access check to an assistant
    /// @param _assistant The assistant
    function delegateAccess(address _assistant) external;

    /// @notice Get token owner
    /// @param _tokenId The token identifier
    /// @return The current owner of the token
    function ownerOf(uint256 _tokenId) external view returns (address);

    /// @notice Get the authorized users of a token
    /// @param _tokenId The token identifier
    /// @return The current authorized users of the token
    function authorizedUsersOf(uint256 _tokenId) external view returns (address[] memory);

    /// @notice Get the approved address for a token
    /// @param _tokenId The token identifier
    /// @return The approved address
    function getApproved(uint256 _tokenId) external view returns (address);

    /// @notice Check if an address is approved for all
    /// @param _owner The owner
    /// @param _operator The operator
    /// @return The approval
    function isApprovedForAll(address _owner, address _operator) external view returns (bool);

    /// @notice Get the delegate access for a user
    /// @param _user The user
    /// @return The delegate access
    function getDelegateAccess(address _user) external view returns (address);
}
