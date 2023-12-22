// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./IOracle.sol";
import "./NameVersion.sol";
import "./SafeMath.sol";

contract OracleChainlink is IOracle, NameVersion {

    using SafeMath for uint256;
    using SafeMath for int256;

    string  public symbol;
    bytes32 public immutable symbolId;

    IChainlinkFeed public immutable feed;
    uint256 public immutable feedDecimals;

    int256  public immutable jumpTimeWindow;

    // stores timestamp/value/jump in 1 slot, instead of 3, to save gas
    // timestamp takes 32 bits, which can hold timestamp range from 1 to 4294967295 (year 2106)
    // value takes 96 bits with accuracy of 1e-18, which can hold value range from 1e-18 to 79,228,162,514.26
    struct Data {
        uint32 timestamp;
        uint96 value;
        int128 jump;
    }
    Data public data;

    constructor (string memory symbol_, address feed_, int256 jumpTimeWindow_) NameVersion('OracleChainlink', '3.0.4') {
        symbol = symbol_;
        symbolId = keccak256(abi.encodePacked(symbol_));
        feed = IChainlinkFeed(feed_);
        feedDecimals = IChainlinkFeed(feed_).decimals();
        jumpTimeWindow = jumpTimeWindow_;
    }

    function timestamp() external view returns (uint256) {
        (uint256 updatedAt, ) = _getLatestRoundData();
        return updatedAt;
    }

    function value() public view returns (uint256 val) {
        (, int256 answer) = _getLatestRoundData();
        val = answer.itou();
        if (feedDecimals != 18) {
            val *= 10 ** (18 - feedDecimals);
        }
    }

    function getValue() external view returns (uint256 val) {
        val = value();
    }

    function _getLatestRoundData() internal view returns (uint256, int256) {
        (uint80 roundId, int256 answer, , uint256 updatedAt, uint80 answeredInRound) = feed.latestRoundData();
        require(answeredInRound >= roundId, 'OracleChainlink._getLatestRoundData: stale');
        require(updatedAt != 0, 'OracleChainlink._getLatestRoundData: incomplete round');
        require(answer > 0, 'OracleChainlink._getLatestRoundData: answer <= 0');
        return (updatedAt, answer);
    }

    function getValueWithJump() external returns (uint256 val, int256 jump) {
        Data memory d = data;
        if (d.timestamp == block.timestamp) {
            // data already updated in current block
            return (d.value, d.jump);
        }

        val = value();
        require(val <= type(uint96).max);

        int256 interval = (block.timestamp - d.timestamp).utoi();
        if (interval < jumpTimeWindow) {
            jump = d.jump * (jumpTimeWindow - interval) / jumpTimeWindow // previous jump impact
                 + (val.utoi() - uint256(d.value).utoi());               // current jump impact
        } else {
            jump = (val.utoi() - uint256(d.value).utoi()) * jumpTimeWindow / interval; // only current jump impact
        }

        data = Data({
            timestamp: uint32(block.timestamp),
            value:     uint96(val),
            jump:      int128(jump) // never overflows
        });
    }

}

interface IChainlinkFeed {
    function decimals() external view returns (uint8);
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}

