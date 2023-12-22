// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.0;

interface IPreLevelConverter {
    /**
     * @notice convert an amount of preLVL to LVL in 1:1 rate
     * @param _preLvlAmount preLVL amount to convert
     * @param _maxTaxAmount max allowed USDT amount to spend
     * @param _to LVL recipient address
     * @param _deadline the conversion must be fulfilled before this timestamp (second) or revert
     */
    function convert(uint256 _preLvlAmount, uint256 _maxTaxAmount, address _to, uint256 _deadline) external;

    /**
     * @notice update LVL/USDT TWAP by authorized party
     *  @param _twap TWAP in precision of 6 decimals
     *  @param _timestamp the time TWAP get calculated
     */
    function updateTWAP(uint256 _twap, uint256 _timestamp) external;

    // ============== EVENTS ==============
    /// @notice emit when TWAP updated
    event TWAPUpdated(uint256 twap, uint256 timestamp);
    /// @notice emit when user converted they preLVL successfully
    event Converted(address indexed user, uint256 amount, uint256 taxAmountToPool, uint256 taxAmountToDao);
    /// @notice emit when new TWAP reporter set
    event PriceReporterSet(address reporter);

    // ============== ERRORS ==============
    /// @notice revert when malicious sender try to execute restricted function
    error Unauthorized();
    /// @notice revert when convert action execute after deadline
    error Timeout();
    /// @notice revert when required tax amount greater than user allowed amount
    error SlippageExceeded(uint256 required, uint256 allowed);
    /// @notice the TWAP did not update intime so cannot be used
    error TWAPOutdated();
    /// @notice TWAP not available yet
    error TWAPNotAvailable();
    /// @notice revert when config with empty LLP list
    error TrancheListIsEmpty();
    /// @notice revert when config invalid LLP address
    error InvalidLLPAddress();
    /// @notice revert when config with address 0 at not allowed place
    error ZeroAddress();
    /// @notice revert when keeper TWAP is too old
    error TwapUpdateTimeout();
    /// @notice revert when keeper TWAP is out of band
    error TwapRejected();
}

