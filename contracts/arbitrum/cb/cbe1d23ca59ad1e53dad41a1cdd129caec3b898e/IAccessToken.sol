// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

struct SignatureData {
    uint8 v;
    bytes32 r;
    bytes32 s;
    uint256 accessKey;
    uint256 nonce;
}

interface IAccessToken {
    event NewAccessKeyAdded(
        uint256 accessKey,
        uint256 index,
        address senderAddress
    );
    event MintingFeeChanged(uint256 newMintingFee);
    event AccessKeyBlacklisted(uint256 blacklistedAccessKey);
    event AddressBlacklisted(address blacklistedAddress);
    event AddressRemovedFromBlacklist(address addressToRestore);

    function blacklistAddresses(address) external view returns (bool);

    function usedNonces(uint256) external view returns (bool);

    function setMintingFee(uint256 _mintingFee) external;

    function addToken(SignatureData memory signatureData) external payable;

    function rootHashExists(uint256 _root) external view returns (bool);

    function getRootHash() external view returns (uint256);

    function blacklistAccessKey(uint256 accessKey, uint256 index) external;

    function blacklistAddress(address _address) external;

    function removeAddressFromBlacklist(address addressToRestore) external;

    function withdraw() external;
}

