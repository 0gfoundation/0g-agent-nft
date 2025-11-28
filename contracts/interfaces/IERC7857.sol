// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {IERC7857DataVerifier, TransferValidityProof} from "./IERC7857DataVerifier.sol";
import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";
import {IERC7857Metadata, IntelligentData} from "./IERC7857Metadata.sol";

interface IERC7857 is IERC721, IERC7857Metadata {
    error ERC7857InvalidAssistant(address);
    error ERC7857EmptyProof();
    error ERC7857ProofCountMismatch();
    error ERC7857DataHashMismatch();
    error ERC7857AccessAssistantMismatch();
    error ERC7857WantedReceiverMismatch();
    error ERC7857EncryptedPubKeyMismatch();

    /// @notice The event minted when data of a token is updated
    /// @param _tokenId the token identifier
    /// @param _oldDatas old token data
    /// @param _newDatas new token data
    event Updated(uint256 indexed _tokenId, IntelligentData[] _oldDatas, IntelligentData[] _newDatas);

    /// @notice The event emitted when a sealed key is published
    /// @param _to The address that is receiving
    /// @param _tokenId The token identifier
    /// @param _sealedKeys The sealed keys
    event PublishedSealedKey(address indexed _to, uint256 indexed _tokenId, bytes[] _sealedKeys);

    /// @notice The event emitted when a user is delegated to an assistant
    /// @param _user The user
    /// @param _assistant The assistant
    event DelegateAccess(address indexed _user, address indexed _assistant);

    /// @notice The verifier interface that this NFT uses
    /// @return The address of the verifier contract
    function verifier() external view returns (IERC7857DataVerifier);

    /// @notice Transfer data with ownership
    /// @param _from Address
    /// @param _to Address to transfer data to
    /// @param _tokenId The token to transfer data for
    /// @param _proofs Proofs of data available for _to
    function iTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId,
        TransferValidityProof[] calldata _proofs
    ) external;

    /// @notice Delegate access check to an assistant
    /// @param _assistant The assistant
    function delegateAccess(address _assistant) external;

    /// @notice Get the delegate access for a user
    /// @param _user The user
    /// @return The delegate access
    function getDelegateAccess(address _user) external view returns (address);
}
