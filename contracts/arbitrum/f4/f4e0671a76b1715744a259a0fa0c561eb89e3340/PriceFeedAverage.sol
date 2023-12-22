// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";
import {Ownable} from "./Ownable.sol";

error NotSameDecimals();
error PriceFeedAOutdated(uint256 lastUpdate);
error PriceFeedBOutdated(uint256 lastUpdate);
error LatestRoundDataAFailed();
error LatestRoundDataBFailed();
error SequencerDown();
error GracePeriodNotOver();
error ZeroAddress();

contract PriceFeedAverage is Ownable {
    // solhint-disable-next-line private-vars-leading-underscore
    uint256 private constant GRACE_PERIOD_TIME = 3600;

    AggregatorV3Interface public immutable priceFeedA;
    AggregatorV3Interface public immutable priceFeedB;
    AggregatorV3Interface public immutable sequencerUptimeFeed;

    uint256 public outdatedA;
    uint256 public outdatedB;

    // #region events.

    event LogSetOutdatedA(
        address oracle,
        uint256 oldOutdated,
        uint256 newOutdated
    );

    event LogSetOutdatedB(
        address oracle,
        uint256 oldOutdated,
        uint256 newOutdated
    );

    // #endregion events.

    constructor(
        address priceFeedA_,
        address priceFeedB_,
        address sequencerUptimeFeed_,
        uint256 outdatedA_,
        uint256 outdatedB_
    ) {
        if(priceFeedA_ == address(0) || priceFeedB_ == address(0))
            revert ZeroAddress();
        priceFeedA = AggregatorV3Interface(priceFeedA_);
        priceFeedB = AggregatorV3Interface(priceFeedB_);

        if (priceFeedA.decimals() != priceFeedB.decimals())
            revert NotSameDecimals();

        sequencerUptimeFeed = AggregatorV3Interface(sequencerUptimeFeed_);

        outdatedA = outdatedA_;
        outdatedB = outdatedB_;
    }

    /// @notice set outdated value for Token A
    /// @param outdatedA_ new outdated value
    function setOutdatedA(uint256 outdatedA_) external onlyOwner {
        uint256 oldOutdatedA = outdatedA;
        outdatedA = outdatedA_;
        emit LogSetOutdatedA(address(this), oldOutdatedA, outdatedA_);
    }

    /// @notice set outdated value for Token B
    /// @param outdatedB_ new outdated value
    function setOutdatedB(uint256 outdatedB_) external onlyOwner {
        uint256 oldOutdatedB = outdatedB;
        outdatedB = outdatedB_;
        emit LogSetOutdatedB(address(this), oldOutdatedB, outdatedB_);
    }

    // solhint-disable-next-line function-max-lines
    function latestRoundData()
        external
        view
        returns (uint80, int256 answer, uint256, uint256 updatedAt, uint80)
    {
        if (address(sequencerUptimeFeed) != address(0)) _checkSequencer();

        int256 priceA;
        int256 priceB;

        uint256 updateAtA;
        uint256 updateAtB;

        try priceFeedA.latestRoundData() returns (
            uint80,
            int256 price,
            uint256,
            uint256 updatedAt,
            uint80
        ) {
            // solhint-disable-next-line not-rely-on-time
            if (block.timestamp - updatedAt > outdatedA)
                revert PriceFeedAOutdated(updatedAt);

            priceA = price;
            updateAtA = updatedAt;
        } catch {
            revert LatestRoundDataAFailed();
        }

        try priceFeedB.latestRoundData() returns (
            uint80,
            int256 price,
            uint256,
            uint256 updatedAt,
            uint80
        ) {
            // solhint-disable-next-line not-rely-on-time
            if (block.timestamp - updatedAt > outdatedB)
                revert PriceFeedBOutdated(updatedAt);

            priceB = price;
            updateAtB = updatedAt;
        } catch {
            revert LatestRoundDataBFailed();
        }

        answer = (priceA + priceB) / 2;
        updatedAt = updateAtA < updateAtB ? updateAtA: updateAtB;
    }

    function decimals() external view returns (uint8) {
        return priceFeedA.decimals();
    }

    // #region view function.

    /// @dev only needed for optimistic L2 chain
    function _checkSequencer() internal view {
        (, int256 answer, uint256 startedAt, , ) = sequencerUptimeFeed
            .latestRoundData();

        if(answer != 0)
            revert SequencerDown();

        // Make sure the grace period has passed after the
        // sequencer is back up.
        // solhint-disable-next-line not-rely-on-time, max-line-length
        if (block.timestamp - startedAt <= GRACE_PERIOD_TIME)
            revert GracePeriodNotOver();
    }

    // #endregion view functions.
}

