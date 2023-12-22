// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IPyth.sol";
import "./PythStructs.sol";
import "./OracleConnector.sol";

contract PythCryptoOracle is OracleConnector {
    IPyth public pyth;
    bytes32 public priceId;

    function getPrice() external view override returns (uint256 price, uint256 timestamp) {
        PythStructs.Price memory currentPrice = pyth.getPrice(priceId);
        price = convertToUint(currentPrice, decimals);
        timestamp = currentPrice.publishTime;
    }

    function validateTimestamp(uint256) external pure override returns (bool) {
        return true;
    }

    constructor(
        address pyth_,
        bytes32 priceId_,
        uint8 decimals_,
        string memory name_
    ) OracleConnector(name_, decimals_) {
        require(pyth_ != address(0), "PythCryptoOracle: Pyth is zero address");
        require(priceId_ != bytes32(0), "PythCryptoOracle: Price id is zero bytes");
        pyth = IPyth(pyth_);
        priceId = priceId_;
    }

    function updatePrice(
        bytes[] calldata updateData
    ) external payable override returns (uint256 price, uint256 timestamp) {
        uint256 updateFee = pyth.getUpdateFee(updateData);
        require(address(this).balance >= updateFee, "PythCryptoOracle: Fee gt balance");
        pyth.updatePriceFeeds{value: updateFee}(updateData);
        PythStructs.Price memory currentPrice = pyth.getPrice(priceId);
        price = convertToUint(currentPrice, decimals);
        timestamp = currentPrice.publishTime;
    }

    function convertToUint(PythStructs.Price memory price, uint8 targetDecimals) private pure returns (uint256) {
        require(price.price >= 0 && price.expo < 0 && price.expo >= -255, "PythCryptoOracle: Invalid price data");
        uint8 priceDecimals = uint8(uint32(-1 * price.expo));
        if (targetDecimals - priceDecimals >= 0) {
            return uint(uint64(price.price)) * 10 ** uint32(targetDecimals - priceDecimals);
        } else {
            return uint(uint64(price.price)) / 10 ** uint32(priceDecimals - targetDecimals);
        }
    }
}

