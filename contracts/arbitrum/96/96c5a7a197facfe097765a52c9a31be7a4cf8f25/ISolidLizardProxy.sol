// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface ISolidLizardProxy {
    function createLock(uint256 _value, uint256 _lockDuration) external returns (uint256 _tokenId);
    function increaseAmount(uint256 value) external;
    function increaseUnlockTime() external;
    function locked() external view returns (uint256 amount, uint256 endTime);
    function resetVote() external;
    function whitelist(address _token) external;
    function SLIZ() external returns (address);
    function ve() external returns (address);
    function solidVoter() external returns (address);
    function pause() external;
    function unpause() external;
    function release() external;
    function claimVeEmissions() external returns (uint256);
    function merge(uint256 _from) external;
    function vote(address[] calldata poolVote, int256[] calldata weights) external;
    function lpInitialized(address lp) external returns (bool);
    function router() external returns (address);

    function getBribeReward(address _lp) external;
    function getTradingFeeReward(address _lp) external;
    function getReward(address _lp) external;

    function tokenId() external view returns (uint256);
    function claimableReward(address _lp) external view returns (uint256);
    function deposit(address _token, uint256 _amount) external;
    function withdraw(address _receiver, address _token, uint256 _amount) external;

    function totalDeposited(address _token) external view returns (uint);
    function totalLiquidityOfGauge(address _token) external view returns (uint);
    function votingBalance() external view returns (uint);
    function votingTotal() external view returns (uint);
}
