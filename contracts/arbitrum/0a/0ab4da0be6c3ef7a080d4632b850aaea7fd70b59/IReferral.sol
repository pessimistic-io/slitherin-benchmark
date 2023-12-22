// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

interface IReferral {
    function codeOwners(bytes32 _code) external view returns (address);

    function ownerCode(address user) external view returns (bytes32);

    function getTraderReferralInfo(
        address _account
    ) external view returns (bytes32, address);

    function setTraderReferralCode(address _account, bytes32 _code) external;

    function getUserParentInfo(
        address owner
    ) external view returns (address parent, uint256 level);

    function getTradeFeeRewardRate(
        address user
    ) external view returns (uint myTransactionReward, uint myReferralReward);

    function govSetCodeOwner(bytes32 _code, address _newAccount) external;

    function updateLPClaimReward(
        address _owner,
        address _parent,
        uint256 _ownerReward,
        uint256 _parentReward
    ) external;

    function updateESLionClaimReward(
        address _owner,
        address _parent,
        uint256 _ownerReward,
        uint256 _parentReward
    ) external;
}

