// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface ILevelNormalVesting {
    struct UserInfo {
        /// @notice Total amount of preLVL tokens user want to convert to LVL.
        uint256 totalVestingAmount;
        /// @notice Accumulate vested preLVL tokens.
        uint256 accVestedAmount;
        /// @notice Amount of LVL tokens the user claimed.
        uint256 claimedAmount;
        /// @notice Last update time of the current vesting process.
        uint256 lastUpdateTime;
    }

    // =============== ERRORS ===============
    error ZeroAddress();
    error ZeroAmount();
    error ZeroVestingAmount();
    error ReserveRateTooHigh();
    error ReserveRateTooLow();
    error ExceededVestableAmount();

    // =============== EVENTS ===============
    event OmniChainStakingSet(address _omniChainStaking);
    event ReserveRateSet(uint256 _reserveRate);
    event FundRecovered(address indexed _to, uint256 _amount);
    event VestingStarted(address indexed _user, uint256 _addedAmount);
    event VestingStopped(
        address indexed _from, address indexed _to, uint256 _totalVestingAmount, uint256 _notVestedAmount
    );
    event Claimed(address indexed _from, address indexed _to, uint256 _amount);

    // =============== FUNCTIONS ===============
    function getReservedAmount(address _user) external view returns (uint256);
    function isFullyVested(address _user) external view returns (bool);
    function claimable(address _user) external view returns (uint256);
    function startVesting(uint256 _amount) external;
    function stopVesting(address _to) external;
    function claim(address _to) external;
    function recoverFund(address _to, uint256 _amount) external;
}

