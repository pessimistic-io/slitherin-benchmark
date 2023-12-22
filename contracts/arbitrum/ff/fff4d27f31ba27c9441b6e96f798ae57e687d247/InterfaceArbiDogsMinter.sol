//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

interface InterfaceArbiDogsMinter {
    event Claim(address indexed requester, uint256 numberOfTokens);
    event SetFee(uint256 fee);
    event SetTreasuryAddress(address treasuryAddress);
    event Initialize(
        address arbiDogsNft,
        uint256 maxMintableTokens,
        address treasuryAddress,
        uint256 fee
    );
    event WhitelistUpdateAdd(uint256 numberOfTokens);
    event WhitelistUpdateRemove(uint256 numberOfTokens);
    event WhitelistEnabled();
    event WhitelistDisabled();
    event MaxMintableTokensChanged(uint256 maxMintableTokens);

    function initialize(
        address _arbiDogsNft,
        uint256 _maxMintableTokens,
        address _treasuryAddress,
        uint256 _fee
    ) external;

    receive() external payable;

    function setFee(uint256 _fee) external;

    function setTreasuryAddress(address _treasuryAddress) external;
}

