// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC7857} from "./IERC7857.sol";

interface IERC7857Authorize is IERC7857 {
    error ERC7857InvalidAuthorizedUser(address);
    error ERC7857TooManyAuthorizedUsers();
    error ERC7857AlreadyAuthorized();
    error ERC7857NotAuthorized();

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

    /// @notice Add authorized user to group
    /// @param _tokenId The token to add to group
    function authorizeUsage(uint256 _tokenId, address _user) external;

    /// @notice Revoke authorization from a user
    /// @param _tokenId The token to revoke authorization from
    /// @param _user The user to revoke authorization from
    function revokeAuthorization(uint256 _tokenId, address _user) external;

    /// @notice Get the authorized users of a token
    /// @param _tokenId The token identifier
    /// @return The current authorized users of the token
    function authorizedUsersOf(uint256 _tokenId) external view returns (address[] memory);
}
