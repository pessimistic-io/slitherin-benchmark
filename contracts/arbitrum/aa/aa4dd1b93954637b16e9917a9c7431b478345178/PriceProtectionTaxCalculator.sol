// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;

import "./SafeMath.sol";
import "./OwnableUpgradeable.sol";
import "./IPriceProtectionTaxCalculator.sol";
import "./SafeToken.sol";

contract PriceProtectionTaxCalculator is IPriceProtectionTaxCalculator, OwnableUpgradeable {
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */

    address public keeper;
    uint256 public override referencePrice;
    mapping(uint256 => uint256) private grvPrices;
    uint256[] private grvPriceWeight;

    /* ========== MODIFIER ========== */

    modifier onlyKeeper() {
        require(
            msg.sender == keeper || msg.sender == owner(),
            "PriceProtectionTaxCalculator: caller is not the owner or keeper"
        );
        _;
    }

    /* ========== INITIALIZER ========== */

    function initialize() external initializer {
        __Ownable_init();
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setKeeper(address _keeper) external onlyOwner {
        require(_keeper != address(0), "PriceProtectionTaxCalculator: invalid keeper address");
        keeper = _keeper;

        emit KeeperUpdated(_keeper);
    }

    function setGrvPrice(uint256 _timestamp, uint256 _price) external override onlyKeeper {
        require(_price > 0, "PriceProtectionTaxCalculator: invalid grv price");
        uint256 truncatedTimestamp = startOfDay(_timestamp);
        if (grvPrices[truncatedTimestamp] == 0) {
            grvPrices[truncatedTimestamp] = _price;
        }

        referencePrice = _calculateReferencePrice(truncatedTimestamp);
        emit PriceUpdated(_timestamp, _price);
    }

    function setGrvPriceWeight(uint256[] calldata weights) external override onlyOwner {
        require(weights.length >= 7 && weights.length <= 30, "PriceProtectionTaxCalculator: invalid grv price weight");
        require(weights[0] >= 0 && weights[0] <= 10, "PriceProtectionTaxCalculator: invalid 1st grv price weight");
        require(weights[1] >= 0 && weights[1] <= 10, "PriceProtectionTaxCalculator: invalid 2nd grv price weight");
        require(weights[2] >= 0 && weights[2] <= 10, "PriceProtectionTaxCalculator: invalid 3rd grv price weight");
        require(weights[3] >= 0 && weights[3] <= 10, "PriceProtectionTaxCalculator: invalid 4th grv price weight");
        require(weights[4] >= 0 && weights[4] <= 10, "PriceProtectionTaxCalculator: invalid 5th grv price weight");
        require(weights[5] >= 0 && weights[5] <= 10, "PriceProtectionTaxCalculator: invalid 6th grv price weight");
        require(weights[6] >= 0 && weights[6] <= 10, "PriceProtectionTaxCalculator: invalid 7th grv price weight");

        grvPriceWeight = weights;

        emit GrvPriceWeightUpdated(weights);
    }

    /// @notice ppt tax test를 위한 임시 reference price 설정 함수
    /// @dev test 후 필요에 따라 제거 가능
    /// @param price price value
    function setReferencePrice(uint256 price) public onlyOwner {
        referencePrice = price;
    }

    /* ========== VIEWS ========== */

    function getGrvPrice(uint256 timestamp) external view override returns (uint256) {
        return grvPrices[startOfDay(timestamp)];
    }

    function startOfDay(uint256 timestamp) public pure override returns (uint256) {
        timestamp = ((timestamp.add(1 days) / 1 days) * 1 days);
        timestamp = timestamp.sub(1 days);
        return timestamp;
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _calculateReferencePrice(uint256 timestamp) private view returns (uint256) {
        uint256 pastDay = timestamp;
        uint256 totalPrice = 0;
        uint256 count = 0;
        for (uint256 i = 0; i < 7; i++) {
            if (grvPrices[pastDay] > 0 && grvPriceWeight.length > i) {
                uint256 weight = grvPriceWeight[i];
                uint256 weightPrice = grvPrices[pastDay].mul(weight);
                totalPrice = totalPrice.add(weightPrice);
                count += weight;
            }
            pastDay = pastDay.sub(1 days);
        }
        uint256 calculatedReferencePrice = count > 0 ? totalPrice.div(count) : 0;
        return calculatedReferencePrice;
    }
}

