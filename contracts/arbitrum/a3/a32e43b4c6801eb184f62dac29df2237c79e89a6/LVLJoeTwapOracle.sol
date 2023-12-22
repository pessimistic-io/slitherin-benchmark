// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {IJoeLBPair} from "./IJoeLBPair.sol";
import {ILVLTwapOracle} from "./ILVLTwapOracle.sol";
import {Uint256x256Math} from "./Uint256x256Math.sol";

/// @notice calculate LVL TWAP from Joe Liquidity Book pair
contract LVLJoeTwapOracle is ILVLTwapOracle {
    using Uint256x256Math for uint256;

    uint256 public constant PRECISION = 1e6;
    uint8 public constant SCALE_OFFSET = 128;

    IJoeLBPair public immutable joeLBPair;
    address public immutable updater;
    uint256 public lastTWAP;
    uint256 public lastUpdated;

    constructor(address _joeLBPair, address _updater) {
        require(_joeLBPair != address(0), "Invalid address");
        joeLBPair = IJoeLBPair(_joeLBPair);
        updater = _updater;
    }

    // =============== VIEW FUNCTIONS ===============

    /**
     * @notice Returns TWAP from the last update time to current time
     */
    function getCurrentTWAP() public view returns (uint256) {
        return getTWAP(lastUpdated, block.timestamp);
    }

    /**
     * @notice returns TWAP between 2 timestamp. The previous one is capped to the oldest sample tracked by oracle
     */
    function getTWAP(uint256 _timestamp1, uint256 _timestamp2) public view returns (uint256 _twap) {
        (,,,, uint40 _firstTimestamp) = joeLBPair.getOracleParameters();
        if (_timestamp1 < _firstTimestamp) {
            _timestamp1 = _firstTimestamp;
        }

        (uint64 _cumulativeId,,) = joeLBPair.getOracleSampleAt(uint40(_timestamp2));
        (uint64 _prevCumulativeId,,) = joeLBPair.getOracleSampleAt(uint40(_timestamp1));

        uint256 _tawId = (_cumulativeId - _prevCumulativeId) / (_timestamp2 - _timestamp1);

        /// convert u128.u128 fixed point number to uint with desired PRECISION
        _twap = joeLBPair.getPriceFromId(uint24(_tawId)).mulShiftRoundDown(1e18, SCALE_OFFSET) * PRECISION;
    }

    // =============== USER FUNCTIONS ===============
    /**
     * @notice update TWAP for last period
     */
    function update() external {
        require(msg.sender == updater, "LVLOracle::updatePrice: !updater");
        lastTWAP = getTWAP(lastUpdated, block.timestamp);
        lastUpdated = block.timestamp;

        emit PriceUpdated(block.timestamp, lastTWAP);
    }

    // ===============  EVENTS ===============
    event PriceUpdated(uint256 timestamp, uint256 price);
}

