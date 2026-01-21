// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

struct IntelligentData {
    string dataDescription;
    bytes32 dataHash;
}

interface IERC7857MetadataLegacy {
    /// @notice Get the name of the NFT collection
    function name() external view returns (string memory);

    /// @notice Get the symbol of the NFT collection
    function symbol() external view returns (string memory);

    /// @notice Get the data hash of a token
    /// @param _tokenId The token identifier
    /// @return The current data hash of the token
    function intelligentDatasOf(uint256 _tokenId) external view returns (IntelligentData[] memory);
}
