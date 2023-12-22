// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./Ownable.sol";
import "./ILBPair.sol";
import "./ILBStrategy.sol";
import "./AutomationCompatible.sol";

/// @title LBPassiveSetBinManager
/// @author SteakHut Finance
/// @notice contract to enable deploying liquidity at a set bin
/// @notice funds are only put to work once the set bin is active and there are minimum idle funds in strategy
/// @notice harvesting of rewards happens on a time schedule
contract LBPassiveSetBinManager is Ownable, AutomationCompatibleInterface {
    address public immutable strategyAddress;
    address public gasCaller;
    uint256 public immutable targetBin;
    uint256 public minAmount = 1e8;

    //gas saving measures
    uint256 public lastTimestamp;
    uint256 public period = 21600; //6 hours

    /// -----------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------

    constructor(
        address _strategyAddress,
        address _gasCaller,
        uint256 _targetBin
    ) {
        strategyAddress = _strategyAddress;
        gasCaller = _gasCaller;
        targetBin = _targetBin;
    }

    /// -----------------------------------------------------------
    /// Manager Functions
    /// -----------------------------------------------------------

    /// @notice Updates fee recipient for gas reimbursement
    /// @param _gasCaller address.
    function setGasCaller(address _gasCaller) external onlyOwner {
        require(address(_gasCaller) != address(0), "Manager: Address 0");
        gasCaller = _gasCaller;
    }

    /// @notice Updates the minimum period between harvests
    /// @param _period new minimum period.
    function setPeriod(uint256 _period) external onlyOwner {
        require(_period > 3600, "Manager: Period too small");
        period = _period;
    }

    /// @notice Updates the minimumAmount required to call earn
    /// @param _minAmount new minimum amount.
    function setMinimumAmount(uint256 _minAmount) external onlyOwner {
        require(_minAmount > 0, "Manager: Min amount too small");
        minAmount = _minAmount;
    }

    /// -----------------------------------------------------------
    /// Chainlink Functions
    /// -----------------------------------------------------------

    /// @notice Chainlink Check Upkeep Function
    /// @notice _harvest should be performed every period (gas saving)
    /// @notice _earn can only be called when certain parameters are active
    function checkUpkeep(
        bytes calldata
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        upkeepNeeded = false;
        ILBStrategy strategy = ILBStrategy(strategyAddress);

        //fetch the current activeId of the lb pair
        address _lbPair = ILBStrategy(strategyAddress).lbPair();
        (, , uint256 activeId) = ILBPair(_lbPair).getReservesAndId();

        // if we have hit the target bin and there are minimum free funds to deploy (gas saving)
        if (
            (activeId == targetBin && strategy.getBalanceX() > minAmount) ||
            (activeId == targetBin && strategy.getBalanceY() > minAmount)
        ) {
            upkeepNeeded = true;
        }

        //require an upkeep if there has been minimum time between harvests
        if (block.timestamp > lastTimestamp + period) {
            upkeepNeeded = true;
        }

        performData; //silence unused parameter
    }

    /// @notice Chainlink Perform Upkeep Function
    /// @notice _harvest may be executed at anytime
    /// @notice _earn can only be called when certain parameters are active
    function performUpkeep(bytes calldata) external override {
        ILBStrategy strategy = ILBStrategy(strategyAddress);

        //fetch the current activeId of the lb pair
        address _lbPair = ILBStrategy(strategyAddress).lbPair();
        (, , uint256 activeId) = ILBPair(_lbPair).getReservesAndId();

        //harvest rewards from strategy; can be called anytime
        _harvest(gasCaller);

        // if we have hit the target bin and there are minimum free funds to deploy (gas saving)
        // place an earn
        if (
            (activeId == targetBin && strategy.getBalanceX() > minAmount) ||
            (activeId == targetBin && strategy.getBalanceY() > minAmount)
        ) {
            _earn();
        }
    }

    /// -----------------------------------------------------------
    /// Internal Functions
    /// -----------------------------------------------------------

    /// @notice executes a harvest of the associated strategy
    /// @param callFeeRecipient address of strategy that needs a harvest
    function _harvest(address callFeeRecipient) internal {
        ILBStrategy strategy = ILBStrategy(strategyAddress);
        strategy.harvest(callFeeRecipient);

        //update the last harvest timestamp
        lastTimestamp = block.timestamp;
    }

    /// @notice executes an earn of the associated strategy
    function _earn() internal {
        ILBStrategy strategy = ILBStrategy(strategyAddress);
        strategy.earn();
    }

    /// -----------------------------------------------------------
    /// END
    /// -----------------------------------------------------------
}

