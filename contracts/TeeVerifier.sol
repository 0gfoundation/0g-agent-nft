// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract TEEVerifier is Initializable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    struct TrustedMeasurements {
        bytes32 mrtd;
        bytes32 rtmr0;
        bytes32 rtmr1;
        bytes32 rtmr2;
        bytes32 rtmr3;
    }

    string public constant VERSION = "1.0.0";

    TrustedMeasurements public trustedConfig;
    address public teeAddress;
    bool public verified;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(bytes memory tdxQuote, TrustedMeasurements memory expected) public initializer {
        TrustedMeasurements memory actual = _extractMeasurements(tdxQuote);

        require(actual.mrtd == expected.mrtd, "Untrusted TD base");
        require(actual.rtmr0 == expected.rtmr0, "Untrusted layer0");
        require(actual.rtmr1 == expected.rtmr1, "Untrusted layer1");
        require(actual.rtmr2 == expected.rtmr2, "Untrusted layer2");
        require(actual.rtmr3 == expected.rtmr3, "Untrusted layer3");

        teeAddress = _extractPublicKey(tdxQuote);

        trustedConfig = expected;
        verified = true;
    }

    function verifyTEESignature(bytes32 dataHash, bytes calldata signature) external view returns (bool) {
        address signer = dataHash.recover(signature);
        return signer == teeAddress;
    }

    function _extractPublicKey(bytes memory quote) internal pure returns (address) {
        // mock, need to extract from quote
        return 0x168752bb1d04b4c93F3ED0a6e8F84534b16F2014;
    }

    function _extractMeasurements(bytes memory quote) internal pure returns (TrustedMeasurements memory) {
        return
            TrustedMeasurements({
                mrtd: bytes32(0),
                rtmr0: bytes32(0),
                rtmr1: bytes32(0),
                rtmr2: bytes32(0),
                rtmr3: bytes32(0)
            });
    }
}
