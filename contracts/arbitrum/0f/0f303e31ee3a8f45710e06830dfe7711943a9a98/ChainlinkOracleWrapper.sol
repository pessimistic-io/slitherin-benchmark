//SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity 0.8.7;

import "./IOracleWrapper.sol";
import "./AggregatorV2V3Interface.sol";

/// @title The oracle management contract for chainlink V3 oracles
contract ChainlinkOracleWrapper is IOracleWrapper {
    // #### Globals
    /**
     * @notice The address of the feed oracle
     */
    address public override oracle;
    address public immutable override deployer;
    uint8 private constant MAX_DECIMALS = 18;
    int256 public scaler;

    // #### Functions
    constructor(address _oracle, address _deployer) {
        require(_oracle != address(0), "Oracle cannot be null");
        require(_deployer != address(0), "Deployer cannot be null");
        oracle = _oracle;
        deployer = _deployer;
        // reset the scaler for consistency
        uint8 _decimals = AggregatorV2V3Interface(oracle).decimals();
        require(_decimals <= MAX_DECIMALS, "COA: too many decimals");
        // scaler is always <= 10^18 and >= 1 so this cast is safe
        unchecked {
            scaler = int256(10**(MAX_DECIMALS - _decimals));
        }
    }

    function decimals() external pure override returns (uint8) {
        return MAX_DECIMALS;
    }

    /**
     * @notice Returns the oracle price in WAD format
     */
    function getPrice() external view override returns (int256) {
        (int256 _price, ) = _latestRoundData();
        return _price;
    }

    /**
     * @return _price The latest round data price
     * @return _data The metadata. Implementations can choose what data to return here. This implementation returns the roundID
     */
    function getPriceAndMetadata() external view override returns (int256, bytes memory) {
        (int256 price, uint80 roundID) = _latestRoundData();
        bytes memory _data = abi.encodePacked(roundID);
        return (price, _data);
    }

    /**
     * @dev An internal function that gets the WAD value price and latest roundID
     */
    function _latestRoundData() internal view returns (int256, uint80) {
        (uint80 roundID, int256 price, , uint256 timeStamp, uint80 answeredInRound) = AggregatorV2V3Interface(oracle)
            .latestRoundData();
        require(answeredInRound >= roundID, "COA: Stale answer");
        require(timeStamp != 0, "COA: Round incomplete");
        return (toWad(price), roundID);
    }

    /**
     * @notice Converts a raw value to a WAD value based on the decimals in the feed
     * @dev This allows consistency for oracles used throughout the protocol
     *      and allows oracles to have their decimals changed without affecting
     *      the market itself
     */
    function toWad(int256 raw) internal view returns (int256) {
        return raw * scaler;
    }

    /**
     * @notice Converts from a WAD value to a raw value based on the decimals in the feed
     */
    function fromWad(int256 wad) external view override returns (int256) {
        return wad / scaler;
    }

    function poll() external pure override returns (int256) {
        return 0;
    }
}

