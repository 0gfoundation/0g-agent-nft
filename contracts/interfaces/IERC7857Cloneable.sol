// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC7857} from "./IERC7857.sol";
import {TransferValidityProof} from "./IERC7857DataVerifier.sol";

interface IERC7857Cloneable is IERC7857 {
    /// @notice The event emitted when a token is cloned
    /// @param _tokenId The token identifier
    /// @param _newTokenId The new token identifier
    /// @param _from The address that is cloning
    /// @param _to The address that is receiving
    event Cloned(uint256 indexed _tokenId, uint256 indexed _newTokenId, address _from, address _to);

    /// @notice Clone data
    /// @param _from Address to clone data from
    /// @param _to Address to clone data to
    /// @param _tokenId The token to clone data for
    /// @param _proofs Proofs of data available for _to
    /// @return _newTokenId The ID of the newly cloned token
    function iCloneFrom(
        address _from,
        address _to,
        uint256 _tokenId,
        TransferValidityProof[] calldata _proofs
    ) external returns (uint256 _newTokenId);
}
