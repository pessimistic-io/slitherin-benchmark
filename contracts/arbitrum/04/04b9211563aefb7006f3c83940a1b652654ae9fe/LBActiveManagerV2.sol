// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./Ownable.sol";
import "./ILBPair.sol";
import "./ILBStrategy.sol";
import "./SafeERC20.sol";
import "./AutomationCompatible.sol";

/// @title LBActiveStratManager V2.1
/// @author SteakHut Finance
/// @notice contract to enable rebalances of the underlying strategy using existing parameters
/// @notice this strategy will chase an active bin once it goes within x number bins of current range
/// @notice this strategy will also perform a rebalance once it becomes one sided
contract LBActiveStratManagerActiveV2 is
    Ownable,
    AutomationCompatibleInterface
{
    using SafeERC20 for IERC20;
    address public immutable strategyAddress;
    uint256 public binOffset;

    //tracks rebalances and attempts to ~equal weight on next rebalance
    bool public isTokenXWeighted;
    bool public isTokenYWeighted;
    uint256 public centerOffset;

    //harvesting params
    uint256 public lastTimestamp;
    uint256 public period = 21600; //6 hours

    /// -----------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------

    constructor(
        address _strategyAddress,
        uint256 _binOffset,
        uint256 _centerOffset
    ) {
        strategyAddress = _strategyAddress;
        binOffset = _binOffset;
        centerOffset = _centerOffset;
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

    /// @notice Updates centerOffset
    /// @param _centerOffset new center offset.
    function setCenterOffset(uint256 _centerOffset) external onlyOwner {
        require(_centerOffset >= 0, "Manager: Center offset too small");
        centerOffset = _centerOffset;
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

    /// @notice manual rebalance underlying position
    function manualRebalance() external onlyOwner {
        //set the weightings to be neutral as manual rebalance
        isTokenYWeighted = false;
        isTokenXWeighted = false;

        //harvest pending rewards
        ILBStrategy(strategyAddress).harvest();

        //execute the rebalance
        ILBStrategy(strategyAddress).executeRebalance();
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
        uint256[] memory activeBins = ILBStrategy(strategyAddress)
            .strategyActiveBins();
        (uint256 minBin, uint256 maxBin) = _checkMinMaxActiveBins(activeBins);

        //get the center of the active bins
        uint256 binLength = activeBins.length;
        uint256 centerBin = binLength / 2;
        uint256 minCenterBin = activeBins[centerBin - centerOffset];
        uint256 maxCenterBin = activeBins[centerBin + centerOffset];

        //fetch the current activeId of the lb pair
        address _lbPair = ILBStrategy(strategyAddress).lbPair();
        uint256 activeId = ILBPair(_lbPair).getActiveId();

        //if the active bin is within binOffset of the active bin rebalance the underlying strategy
        if (activeId <= minBin + binOffset) {
            upkeepNeeded = true;
        }
        if (activeId >= maxBin - binOffset) {
            upkeepNeeded = true;
        }

        //if the ratio is skewed rebalance to get ratio back to equal weight
        if (
            (activeId <= minCenterBin && isTokenYWeighted) ||
            (activeId >= maxCenterBin && isTokenXWeighted)
        ) {
            //requires upkeep to equal weight bins
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
        uint256 activeId = ILBPair(_lbPair).getActiveId();

        //fetch the active bins in the strategy
        uint256[] memory activeBins = ILBStrategy(strategyAddress)
            .strategyActiveBins();

        // check the min and max active bins
        (uint256 minBin, uint256 maxBin) = _checkMinMaxActiveBins(activeBins);

        //get the center of the active bins
        uint256 binLength = activeBins.length;
        uint256 centerBin = binLength / 2;
        uint256 minCenterBin = activeBins[centerBin - centerOffset];
        uint256 maxCenterBin = activeBins[centerBin + centerOffset];

        //revalidating the upkeep in the performUpkeep function
        //if the active bin is within binOffset of the active bin rebalance the underlying strategy
        //idle strategy funds are put to work on the next rebalance
        //we dont need to check bin limit as funds will always be the underlying bin length
        if (activeId <= minBin + binOffset || activeId >= maxBin - binOffset) {
            //the liquidty upon this rebalance will be skewed so turn on trigger switch for next
            if (activeId <= minBin + binOffset) {
                //strategy is token X weighted
                isTokenXWeighted = true;
                isTokenYWeighted = false;
            }
            if (activeId >= maxBin - binOffset) {
                //strategy is token Y weighted
                isTokenXWeighted = false;
                isTokenYWeighted = true;
            }

            //harvest pending rewards
            _harvest();

            //rebalance keeping the same parameters as before
            ILBStrategy(strategyAddress).executeRebalance();
        } else if (
            (activeId <= minCenterBin && isTokenYWeighted) ||
            (activeId >= maxCenterBin && isTokenXWeighted)
        ) {
            //reset the weighting switch
            isTokenYWeighted = false;
            isTokenXWeighted = false;

            //harvest pending rewards
            _harvest();

            //rebalance keeping the same parameters as before
            //does not require a harvest as executeRebalance handles this
            ILBStrategy(strategyAddress).executeRebalance();
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

