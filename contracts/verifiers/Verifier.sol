// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./base/BaseVerifier.sol";
import "../interfaces/IERC7857DataVerifier.sol";
import "../TeeVerifier.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

struct AttestationConfig {
    OracleType oracleType;
    address contractAddress;
}

contract Verifier is
    BaseVerifier,
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable
{
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    event AttestationContractUpdated(AttestationConfig[] attestationConfigs);

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    mapping(OracleType => address) public attestationContract;

    uint256 public maxProofAge;

    string public constant VERSION = "2.0.0";

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        AttestationConfig[] calldata _attestationConfigs,
        address _admin
    ) external initializer {
        __AccessControl_init();
        __Pausable_init();

        for (uint256 i = 0; i < _attestationConfigs.length; i++) {
            attestationContract[
                _attestationConfigs[i].oracleType
            ] = _attestationConfigs[i].contractAddress;
        }
        maxProofAge = 7 days;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);

        emit AttestationContractUpdated(_attestationConfigs);
    }

    function updateAttestationContract(
        AttestationConfig[] calldata _attestationConfigs
    ) external onlyRole(ADMIN_ROLE) {
        for (uint256 i = 0; i < _attestationConfigs.length; i++) {
            attestationContract[
                _attestationConfigs[i].oracleType
            ] = _attestationConfigs[i].contractAddress;
        }

        emit AttestationContractUpdated(_attestationConfigs);
    }

    function updateMaxProofAge(
        uint256 _maxProofAge
    ) external onlyRole(ADMIN_ROLE) {
        maxProofAge = _maxProofAge;
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function hashNonce(bytes memory nonce) private pure returns (bytes32) {
        return keccak256(nonce);
    }

    function teeOracleVerify(
        bytes32 messageHash,
        bytes memory signature
    ) internal view returns (bool) {
        return
            TEEVerifier(attestationContract[OracleType.TEE]).verifyTEESignature(
                messageHash,
                signature
            );
    }

    /// @notice Extract and verify signature from the access proof
    /// @param accessProof The access proof
    /// @return The recovered access assistant address
    function verifyAccessibility(
        AccessProof memory accessProof
    ) private pure returns (address) {
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n66",
                Strings.toHexString(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                accessProof.oldDataHash,
                                accessProof.newDataHash,
                                accessProof.encryptedPubKey,
                                accessProof.nonce
                            )
                        )
                    ),
                    32
                )
            )
        );

        address accessAssistant = messageHash.recover(accessProof.proof);
        require(accessAssistant != address(0), "Invalid access assistant");
        return accessAssistant;
    }

    function verfifyOwnershipProof(
        OwnershipProof memory ownershipProof
    ) private view returns (bool) {
        if (ownershipProof.oracleType == OracleType.TEE) {
            bytes32 messageHash = keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n66",
                    Strings.toHexString(
                        uint256(
                            keccak256(
                                abi.encodePacked(
                                    ownershipProof.oldDataHash,
                                    ownershipProof.newDataHash,
                                    ownershipProof.sealedKey,
                                    ownershipProof.encryptedPubKey,
                                    ownershipProof.nonce
                                )
                            )
                        ),
                        32
                    )
                )
            );

            return teeOracleVerify(messageHash, ownershipProof.proof);
        }
        // TODO: add ZKP verification
        else {
            return false;
        }
    }

    /// @notice Process a single transfer validity proof
    /// @param proof The proof data
    /// @return output The processed proof data as a struct
    function processTransferProof(
        TransferValidityProof calldata proof
    ) private view returns (TransferValidityProofOutput memory output) {
        // compare the proof data in access proof and ownership proof
        require(
            proof.accessProof.oldDataHash == proof.ownershipProof.oldDataHash,
            "Invalid oldDataHashes"
        );
        output.oldDataHash = proof.accessProof.oldDataHash;
        require(
            proof.accessProof.newDataHash == proof.ownershipProof.newDataHash,
            "Invalid newDataHashes"
        );
        output.newDataHash = proof.accessProof.newDataHash;

        output.wantedKey = proof.accessProof.encryptedPubKey;
        output.accessProofNonce = proof.accessProof.nonce;
        output.encryptedPubKey = proof.ownershipProof.encryptedPubKey;
        output.sealedKey = proof.ownershipProof.sealedKey;
        output.ownershipProofNonce = proof.ownershipProof.nonce;

        // verify the access assistant
        output.accessAssistant = verifyAccessibility(proof.accessProof);

        bool isOwn = verfifyOwnershipProof(proof.ownershipProof);

        require(isOwn, "Invalid ownership proof");

        return output;
    }

    /// @notice Verify data transfer validity, the _proof prove:
    ///         1. The pre-image of oldDataHashes
    ///         2. The oldKey can decrypt the pre-image and the new key re-encrypt the plaintexts to new ciphertexts
    ///         3. The newKey is encrypted with the receiver's pubKey to get the sealedKey
    ///         4. The hashes of new ciphertexts is newDataHashes (key to note: TEE could support a private key of the receiver)
    ///         5. The newDataHashes identified ciphertexts are available in the storage: need the signature from the receiver signing oldDataHashes and newDataHashes
    /// @param proofs Proof generated by TEE/ZKP oracle
    function verifyTransferValidity(
        TransferValidityProof[] calldata proofs
    )
        public
        virtual
        override
        whenNotPaused
        returns (TransferValidityProofOutput[] memory)
    {
        TransferValidityProofOutput[]
            memory outputs = new TransferValidityProofOutput[](proofs.length);

        for (uint256 i = 0; i < proofs.length; i++) {
            TransferValidityProofOutput memory output = processTransferProof(
                proofs[i]
            );

            outputs[i] = output;

            bytes32 accessProofNonce = hashNonce(output.accessProofNonce);
            _checkAndMarkProof(accessProofNonce);

            bytes32 ownershipProofNonce = hashNonce(output.ownershipProofNonce);
            _checkAndMarkProof(ownershipProofNonce);
        }

        return outputs;
    }

    uint256[50] private __gap;
}
