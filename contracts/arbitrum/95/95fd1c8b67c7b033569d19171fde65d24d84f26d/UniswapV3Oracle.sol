// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "./OracleLibrary.sol";
import "./AggregatorV3Interface.sol";

interface IV3SwapRouter {
    function factory() external view returns(address);
    function WETH9() external view returns(address);
}

interface IV3Factory {
    function getPool(address,address,uint24) external view returns(address);
}

interface IV3Pool {
    function liquidity() external view returns(uint);
    function token0() external view returns(address);
    function token1() external view returns(address);
}

interface IERC20Metadata {
    function decimals() external view returns (uint8);
}

contract UniswapV3Oracle {
    address public token;
    address public money;
    address public poolAddress;
    address public token0;
    string public description;
    uint24 public  fee;
    uint256 public decimals;
    uint256 public tokenDecimals;
    uint256 public moneyDecimals;
    AggregatorV3Interface public priceFeed;
    uint8 public priceFeedDecimals;

    constructor(string memory _description, address _factory, address _token, address _money, uint24 _fee, AggregatorV3Interface _priceFeed) {
        token = _token;
        money = _money;
        fee = _fee;
        poolAddress = IV3Factory(_factory).getPool(_token, _money, _fee);
        token0 = IV3Pool(poolAddress).token0();
        description = _description;
        decimals = 8;
        tokenDecimals = IERC20Metadata(_token).decimals();
        moneyDecimals = IERC20Metadata(_money).decimals();
        priceFeed = _priceFeed;
        if (address(priceFeed) != address(0)) {
            priceFeedDecimals = priceFeed.decimals();
        }
	}

    function latestRoundData() external view returns(
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
        uint256 p = getPriceV3(poolAddress, token0, token, tokenDecimals, moneyDecimals) * (10 ** decimals) / 1e27;
        if (address(priceFeed) != address(0)) {
            (,int256 answer0,,,) = priceFeed.latestRoundData();
            p = p * uint256(answer0) / (10 ** priceFeedDecimals);
        }
        answer = int256(p);
        startedAt = block.timestamp;
        updatedAt = block.timestamp;
    }

    function getPriceV3(address _poolAddress, address _token0, address _token, uint256 _tokenDecimals, uint256 _moneyDecimals) internal view returns (uint256 price) {
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(_poolAddress).slot0();
        uint256 P = uint256(sqrtPriceX96) * 1e27 >> 96;
        uint256 priceWei = P * P / 1e27;
        if(_token != _token0){
            priceWei = 1e27 * 1e27 / priceWei;
        }  
        price = priceWei * (10 ** _tokenDecimals) / (10 ** _moneyDecimals);
    }
}

