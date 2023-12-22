// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUnlockProtocol {
    function updateKeyPricing(uint256 _keyPrice, address _tokenAddress)
        external;

    function renounceLockManager() external;

    function setLockMetadata(
        string calldata _lockName,
        string calldata _lockSymbol,
        string calldata _baseTokenURI
    ) external;

    function setReferrerFee(address _referrer, uint256 _feeBasisPoint) external;

    function setEventHooks(
        address _onKeyPurchaseHook,
        address _onKeyCancelHook,
        address _onValidKeyHook,
        address _onTokenURIHook,
        address _onKeyTransferHook,
        address _onKeyExtendHook,
        address _onKeyGrantHook
    ) external;

    function burn(uint256 _tokenId) external;

    function addLockManager(address account) external;

    function setOwner(address account) external;

    function grantRole(bytes32 role, address account) external;

    function updateLockConfig(
        uint256 _newExpirationDuration,
        uint256 _maxNumberOfKeys,
        uint256 _maxKeysPerAcccount
    ) external;

    function grantKeys(
        address[] calldata _recipients,
        uint256[] calldata _expirationTimestamps,
        address[] calldata _keyManagers
    ) external;

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) external;

    function setKeyManagerOf(uint256 _tokenId, address _keyManager) external;

    function withdraw(
        address _tokenAddress,
        address payable _recipient,
        uint256 _amount
    ) external;
}

