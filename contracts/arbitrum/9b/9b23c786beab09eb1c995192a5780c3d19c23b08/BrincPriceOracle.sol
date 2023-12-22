// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./Ownable.sol";
import "./SafeMath.sol";
import "./ERC20.sol";

import "./PriceOracle.sol";
import "./CErc20.sol";

import "./AggregatorV3Interface.sol";

import "./BasePriceOracle.sol";

interface IBrincToken {
  function mintCost(uint256 amount) external view returns (uint256);
}

contract BrincPriceOracle is Ownable, PriceOracle, BasePriceOracle {
  using SafeMath for uint256;

  address public brincToken;

  AggregatorV3Interface public DAI_USD_ORACLE = AggregatorV3Interface(0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB); // DAI/USD Chainlink Price Feed on Arbitrum

  AggregatorV3Interface public ETH_USD_ORACLE = AggregatorV3Interface(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612); // ETH/USD Chainlink Price Feed on Arbitrum

  event BrincTokenUpdated(address indexed newBrincToken, address indexed oldBrincToken);

  constructor(address _brincToken) public {
    require(_brincToken != address(0), "invalid brinc token address");
    brincToken = _brincToken;
  }

  function updateBrincToken(address _newBrincToken) external onlyOwner {
    require(_newBrincToken != address(0), "invalid brinc token address");
    require(_newBrincToken != brincToken, "invalid brinc token address");

    address oldBrincToken = brincToken;
    brincToken = _newBrincToken;

    emit BrincTokenUpdated(brincToken, oldBrincToken);
  }

  function latestAnswer() public view returns (int256) {
    uint256 daiPerBRC = IBrincToken(brincToken).mintCost(1e18);
    return int256(daiPerBRC.div(1e10));
  }

  /**
    * @notice Fetches the token/ETH price, with 18 decimals of precision.
    * @param underlying The underlying token address for which to get the price.
    * @return Price denominated in ETH (scaled by 1e18)
    */
  function price(address underlying) external override view returns (uint) {
    return _price(underlying);
  }

  /**
    * @notice Returns the price in ETH of the token underlying `cToken`.
    * @dev Implements the `PriceOracle` interface for Fuse pools (and Compound v2).
    * @return Price in ETH of the token underlying `cToken`, scaled by `10 ** (36 - underlyingDecimals)`.
    */
  function getUnderlyingPrice(CToken cToken) external override view returns (uint) {
    address underlying = CErc20(address(cToken)).underlying();
    // Comptroller needs prices to be scaled by 1e(36 - decimals)
    // Since `_price` returns prices scaled by 18 decimals, we must scale them by 1e(36 - 18 - decimals)
    return _price(underlying).mul(1e18).div(10 ** uint256(ERC20(underlying).decimals()));
  }

  /**
    * @notice Fetches the token/ETH price, with 18 decimals of precision.
    */
  function _price(address token) internal view returns (uint) {
    require(token == brincToken, "Invalid token passed to BrincPriceOracle.");

    (, int256 daiIndex, , , ) = DAI_USD_ORACLE.latestRoundData();
    (, int256 ethIndex, , , ) = ETH_USD_ORACLE.latestRoundData();

    uint256 daiPerBRC = IBrincToken(brincToken).mintCost(1e18);
    return daiPerBRC.mul(uint256(daiIndex)).div(uint256(ethIndex)).div(1e10);
  }
}

