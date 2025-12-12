// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Utils {
    function bytesToHexString(bytes memory data) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(2 * data.length);
        
        for (uint i = 0; i < data.length; i++) {
            str[2 * i] = alphabet[uint8(data[i] >> 4)];
            str[2 * i + 1] = alphabet[uint8(data[i] & 0x0f)];
        }
        
        return string(str);
    }

    function bytesEqual(
        bytes memory arr1,
        bytes memory arr2
    ) internal pure returns (bool) {
        if (arr1.length != arr2.length) {
            return false;
        }
        for (uint i = 0; i < arr1.length; i++) {
            if (arr1[i] != arr2[i]) {
                return false;
            }
        }
        return true;
    }

    function pubKeyToAddress(
        bytes memory pubKey
    ) internal pure returns (address) {
        require(pubKey.length == 64, "Invalid public key length");
        bytes32 hash = keccak256(pubKey);
        return address(uint160(uint256(hash)));
    }
}
