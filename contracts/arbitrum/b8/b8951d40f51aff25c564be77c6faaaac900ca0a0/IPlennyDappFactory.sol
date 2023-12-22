// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

interface IPlennyDappFactory {

    function isOracleValidator(address validatorAddress) external view returns (bool);

    // to be removed from factory
    function random() external view returns (uint256);

    function decreaseDelegatedBalance(address dapp, uint256 amount) external;

    function increaseDelegatedBalance(address dapp, uint256 amount) external;

    function updateReputation(address validator, uint256 electionBlock) external;

    function getValidatorsScore() external view returns (uint256[] memory scores, uint256 sum);

    function getDelegatedBalance(address) external view returns (uint256);

    function getDelegators(address) external view returns (address[] memory);

    function pureRandom() external view returns (uint256);

    function validators(uint256 index) external view returns (string memory name, uint256 nodeIndex, string memory nodeIP,
        string memory nodePort, string memory validatorServiceUrl, uint256 revenueShareGlobal, address owner, uint256 reputation);

    function validatorIndexPerAddress(address addr) external view returns (uint256 index);

    function userChannelRewardPeriod() external view returns (uint256);

    function userChannelReward() external view returns (uint256);

    function userChannelRewardFee() external view returns (uint256);

    function makersFixedRewardAmount() external view returns (uint256);

    function makersRewardPercentage() external view returns (uint256);

    function capacityFixedRewardAmount() external view returns (uint256);

    function capacityRewardPercentage() external view returns (uint256);

    function defaultLockingAmount() external view returns (uint256);
}
