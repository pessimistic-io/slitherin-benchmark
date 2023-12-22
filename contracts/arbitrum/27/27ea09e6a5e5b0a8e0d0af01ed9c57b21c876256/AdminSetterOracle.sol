// SPDX-License-Identifier: Apache-2.0

pragma solidity =0.8.9;

import "./IAaveV3LendingPool.sol";
import "./CompoundingRateOracle.sol";

contract AdminSetterOracle is CompoundingRateOracle {
    struct RateUpdate {
        uint32 timestamp;
        uint256 rate;
    }

    address public admin;
    RateUpdate public lastRateUpdate;

    uint8 public immutable override UNDERLYING_YIELD_BEARING_PROTOCOL_ID;

    // token address of the underlying asset on the chain the rate is sourced from
    IERC20Minimal public immutable sourceUnderlying;

    // chain id of the chain the rate is sourced from
    uint256 public immutable sourceChainId;

    constructor(
        address _admin,
        uint8 _underlyingYieldBearingProtocolId,
        IERC20Minimal _underlying,
        uint256 _currentRate,
        uint32[] memory _times,
        uint256[] memory _results,
        IERC20Minimal _sourceUnderlying,
        uint256 _sourceChainId
    ) BaseRateOracle(_underlying) {
        // Check that underlying was set in BaseRateOracle
        require(address(underlying) != address(0), "underlying must exist");

        lastRateUpdate = RateUpdate({
            timestamp: Time.blockTimestampTruncated(),
            rate: _currentRate
        });

        admin = _admin;
        sourceUnderlying = _sourceUnderlying;
        sourceChainId = _sourceChainId;

        UNDERLYING_YIELD_BEARING_PROTOCOL_ID = _underlyingYieldBearingProtocolId;

        _populateInitialObservations(_times, _results, true);
    }

    function setLastUpdatedRate(uint256 _rate) external {
        require(msg.sender == admin, "only admin");
        lastRateUpdate = RateUpdate({
            timestamp: Time.blockTimestampTruncated(),
            rate: _rate
        });

        emit LastRateUpdated(_rate);
    }

    function setAdmin(address _admin) external {
        require(msg.sender == admin, "only admin");
        emit AdminUpdated(admin, _admin);
        admin = _admin;
    }

    /// @inheritdoc BaseRateOracle
    function getLastUpdatedRate()
        public
        view
        override
        returns (uint32 timestamp, uint256 resultRay)
    {
        return (lastRateUpdate.timestamp, lastRateUpdate.rate);
    }

    event LastRateUpdated(uint256 rate);
    event AdminUpdated(address oldAdmin, address newAdmin);
}

