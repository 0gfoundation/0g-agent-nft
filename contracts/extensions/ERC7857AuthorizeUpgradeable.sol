// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {ERC7857Upgradeable} from "../ERC7857Upgradeable.sol";
import {IERC7857Authorize} from "../interfaces/IERC7857Authorize.sol";
import {IntelligentData} from "../interfaces/IERC7857Metadata.sol";

contract ERC7857AuthorizeUpgradeable is IERC7857Authorize, ERC7857Upgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint public constant MAX_AUTHORIZED_USERS = 100;

    /// @custom:storage-location erc7857:0g.storage.ERC7857Authorize
    struct ERC7857AuthorizeStorage {
        mapping(uint tokenId => EnumerableSet.AddressSet) authorizedUsers;
    }

    // keccak256(abi.encode(uint256(keccak256("0g.storage.ERC7857Authorize")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC7857AuthorizeStorageLocation =
        0xf386e9faca35fbde2fe950510f665060c1dd15a136a76c268b6e6459b9945700;

    function _getERC7857AuthorizeStorage() private pure returns (ERC7857AuthorizeStorage storage $) {
        assembly {
            $.slot := ERC7857AuthorizeStorageLocation
        }
    }

    function authorizedUsersOf(uint256 tokenId) public view virtual returns (address[] memory) {
        ERC7857AuthorizeStorage storage $ = _getERC7857AuthorizeStorage();
        if (_ownerOf(tokenId) == address(0)) {
            revert ERC721NonexistentToken(tokenId);
        }
        return $.authorizedUsers[tokenId].values();
    }

    function _authorizeUsage(uint256 tokenId, address to) internal {
        ERC7857AuthorizeStorage storage $ = _getERC7857AuthorizeStorage();

        EnumerableSet.AddressSet storage authorizedUsers = $.authorizedUsers[tokenId];

        if (authorizedUsers.length() >= MAX_AUTHORIZED_USERS) {
            revert ERC7857TooManyAuthorizedUsers();
        }

        if (authorizedUsers.contains(to)) {
            revert ERC7857AlreadyAuthorized();
        }

        authorizedUsers.add(to);

        emit Authorization(msg.sender, to, tokenId);
    }

    function _clearAuthorized(uint tokenId) internal {
        ERC7857AuthorizeStorage storage $ = _getERC7857AuthorizeStorage();
        address[] memory values = $.authorizedUsers[tokenId].values();
        for (uint i = 0; i < values.length; ++i) {
            $.authorizedUsers[tokenId].remove(values[i]);
        }
    }

    function authorizeUsage(uint256 tokenId, address to) public virtual {
        if (to == address(0)) {
            revert ERC7857InvalidAuthorizedUser(address(0));
        }

        if (_ownerOf(tokenId) != msg.sender) {
            revert ERC721IncorrectOwner(msg.sender, tokenId, _ownerOf(tokenId));
        }

        _authorizeUsage(tokenId, to);
    }

    function revokeAuthorization(uint256 tokenId, address user) public virtual {
        ERC7857AuthorizeStorage storage $ = _getERC7857AuthorizeStorage();
        if (_ownerOf(tokenId) != msg.sender) {
            revert ERC721InvalidSender(msg.sender);
        }
        if (user == address(0)) {
            revert ERC7857InvalidAuthorizedUser(user);
        }

        if (!$.authorizedUsers[tokenId].remove(user)) {
            revert ERC7857NotAuthorized();
        }

        emit AuthorizationRevoked(msg.sender, user, tokenId);
    }

    /*=== override ERC721 ===*/

    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) {
        address from = super._update(to, tokenId, auth);
        // clear authorized users
        _clearAuthorized(tokenId);
        return from;
    }
}
