// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./AutomationCompatible.sol";

import "./ILBPair.sol";

import "./ILBStrategy.sol";

/// @title LBStrategyMonitor
/// @notice contract to enable rebalances of the underlying strategy using existing parameters
/// @notice this strategy will chase an active bin once it goes within x number bins of current range
contract LBStrategyMonitor is Ownable, AutomationCompatibleInterface {
    using SafeERC20 for IERC20;
    address public immutable strategyAddress;
    uint256 public binOffset;

    //harvesting params
    uint256 public lastTimestamp;
    uint256 public period = 604800; //7 days
    address public gasCaller;

    /// -----------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------

    constructor(
        address _strategyAddress,
        address _gasCaller,
        uint256 _binOffset
    ) {
        strategyAddress = _strategyAddress;
        binOffset = _binOffset;
        gasCaller = _gasCaller;

        lastTimestamp = block.timestamp;
    }

    /// -----------------------------------------------------------
    /// Manager Functions
    /// -----------------------------------------------------------

    /// @notice Updates binOffset
    /// @param _binOffset new bin offset.
    function setBinOffset(uint256 _binOffset) external onlyOwner {
        require(_binOffset >= 0, "Manager: Bin offset too small");
        binOffset = _binOffset;
    }

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

    /// @notice Rescues funds stuck
    /// @param _token address of the token to rescue.
    function inCaseTokensGetStuck(address _token) external onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);
    }

    /// -----------------------------------------------------------
    /// View / Pure Functions
    /// -----------------------------------------------------------

    /// @notice returns the minimum and maximum bin currently used by the underlying strategy
    function _checkMinMaxActiveBins(
        uint256[] memory activeBins
    ) public pure returns (uint256 minBin, uint256 maxBin) {
        //do a first run and set min bin to the first item
        bool isFirstRun = true;

        for (uint256 i; i < activeBins.length; i++) {
            if (activeBins[i] < minBin || isFirstRun) {
                minBin = activeBins[i];
                isFirstRun = false;
            }
            if (activeBins[i] > maxBin) {
                maxBin = activeBins[i];
            }
        }
    }

    /// -----------------------------------------------------------
    /// Chainlink Functions
    /// -----------------------------------------------------------

    /// @notice Chainlink Check Upkeep Function
    /// @notice checks to moves liquidity around the active bin once binOffset is achieved
    /// @notice checks if enough time has passed to perform a harvest only
    function checkUpkeep(
        bytes calldata
    )
    external
    view
    override
    returns (bool upkeepNeeded, bytes memory performData)
    {
        upkeepNeeded = false;

        //fetch all the active bins in the strategy
        uint256[] memory activeBins = ILBStrategy(strategyAddress).strategyActiveBins();

        (uint256 minBin, uint256 maxBin) = _checkMinMaxActiveBins(activeBins);

        //fetch the current activeId of the lb pair
        address _lbPair = ILBStrategy(strategyAddress).lbPair();
        (, , uint256 activeId) = ILBPair(_lbPair).getReservesAndId();

        //if the active bin is within binOffset of the active bin rebalance the underlying strategy
        if (activeId <= minBin + binOffset) {
            upkeepNeeded = true;
        }
        if (activeId >= maxBin - binOffset) {
            upkeepNeeded = true;
        }

        //require an upkeep if there has been minimum time between harvests
        if (block.timestamp > lastTimestamp + period) {
            upkeepNeeded = true;
        }

        performData; //silence unused parameter
    }

    /// @notice Chainlink Perform Upkeep Function
    /// @notice moves liquidity around the active bin once binOffset is achieved
    /// @notice harvest if enough time has passed to perform a harvest only
    function performUpkeep(bytes calldata) external override {
        //get the underlying lbPair and activeId
        address _lbPair = ILBStrategy(strategyAddress).lbPair();
        (, , uint256 activeId) = ILBPair(_lbPair).getReservesAndId();

        //fetch the active bins in the strategy
        uint256[] memory activeBins = ILBStrategy(strategyAddress).strategyActiveBins();

        (uint256 minBin, uint256 maxBin) = _checkMinMaxActiveBins(activeBins);

        //revalidating the upkeep in the performUpkeep function
        //if the active bin is within binOffset of the active bin rebalance the underlying strategy
        //idle strategy funds are put to work on the next rebalance
        //we dont need to check bin limit as funds will always be the underlying bin length
        if (activeBins.length > 0 && (activeId <= minBin + binOffset || activeId >= maxBin - binOffset)) {
            //rebalance keeping the same parameters as before
            //does not require a harvest as executeRebalance handles this
            ILBStrategy(strategyAddress).executeRebalance();

            lastTimestamp = block.timestamp;
        } else {
            //harvest rewards from strategy; can be called anytime
            _harvest();
        }
    }

    /// -----------------------------------------------------------
    /// Internal Functions
    /// -----------------------------------------------------------

    /// @notice executes a harvest of the associated strategy
    function _harvest() internal {
        ILBStrategy strategy = ILBStrategy(strategyAddress);
        strategy.harvest();

        //update the last harvest timestamp
        lastTimestamp = block.timestamp;
    }

    /// -----------------------------------------------------------
    /// END
    /// -----------------------------------------------------------
}
