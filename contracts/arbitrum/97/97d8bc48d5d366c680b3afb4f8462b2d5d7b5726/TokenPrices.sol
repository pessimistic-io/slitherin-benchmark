// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./AccessControl.sol";
import "./Context.sol";
import "./ERC20.sol";

import "./AggregatorV3Interface.sol";

import "./OracleCharger.sol";

interface IUniswapV2Pair_Like {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

interface IUniswapV3Pool_Like {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function liquidity() external view returns (uint128);
    function slot0() external view returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol, bool unlocked);
}

contract TokenPrices is 
    Context,
    AccessControl,
    TokenPriceOracle 
{
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    uint8 public constant DefiPoolType_UniswapV2 = 1;
    uint8 public constant DefiPoolType_UniswapV3 = 2;
    
    uint256 internal constant Q96 = 0x1000000000000000000000000;

    struct DefiPoolConf {
        uint8 poolType;
        uint8 tokenIndex;
        address poolAddr;
    }

    mapping(address=>AggregatorV3Interface) public _chainLinkFeeds;
    mapping(address=>DefiPoolConf) public _defiPools;

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        _setupRole(MANAGER_ROLE, _msgSender());
    }

    /**
     * (ETH)Arbitrum Goerli Testnet : 0x62CAe0FA2da220f43a51F86Db2EDb36DcA9A5A08
     * (ETH)Arbitrum One : 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612
     */
    function setChainLinkTokenPriceSource(address tokenAddr, address feedAddr) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "MTTMinePool: must have manager role");

        _chainLinkFeeds[tokenAddr] = AggregatorV3Interface(feedAddr);
    }
    
    function setDefiPoolSource(address tokenAddr, DefiPoolConf memory defiPoolSource) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "MTTMinePool: must have manager role");

        _defiPools[tokenAddr] = defiPoolSource;
    }

    /**
     * Returns the latest price.
     */
    function getERC20TokenUSDPrice(address tokenAddr) public override view returns (uint256) {

        if(address(_chainLinkFeeds[tokenAddr]) != address(0)){

            // prettier-ignore
            (
                /* uint80 roundID */,
                int price,
                /*uint startedAt*/,
                /*uint timeStamp*/,
                /*uint80 answeredInRound*/
            ) = _chainLinkFeeds[tokenAddr].latestRoundData();
            require(price > 0, "price error");

            return uint256(price);
        }

        DefiPoolConf storage defiPool = _defiPools[tokenAddr];
        if(defiPool.poolType != 0){

            // get price from defi pool
            if(defiPool.poolType == DefiPoolType_UniswapV2) {
                if(defiPool.tokenIndex == 0){
                    return _univ2_getTokenPrice_0(defiPool.poolAddr, 1*(10**ERC20(tokenAddr).decimals()));
                }
                else {
                    return _univ2_getTokenPrice_1(defiPool.poolAddr, 1*(10**ERC20(tokenAddr).decimals()));
                }
            }
            else if(defiPool.poolType == DefiPoolType_UniswapV3){
                if(defiPool.tokenIndex == 0){
                    return _univ3_getTokenPrice_0(defiPool.poolAddr, 1*(10**ERC20(tokenAddr).decimals()));
                }
                else {
                    return _univ3_getTokenPrice_1(defiPool.poolAddr, 1*(10**ERC20(tokenAddr).decimals()));
                }
            }
            else {
                revert("defiPool.poolType not exist"); 
            }

            // // for Debug ...
            // return 9000000; // 0.09 u
        }

        revert("token price source not set");
    }

    function _sync_usdprice_decimals8(uint256 price, uint8 decimals) internal pure returns(uint256 ret) {

        if(decimals < 8){
            ret = price * (10**(8 - decimals));
        }
        else if(decimals > 8){
            ret = price / (10**(decimals - 8));
        }
        else {
            ret = price;
        }

        return ret;
    }

    // uniswap v2 get token price ---------------------------------------------
    // calculate price based on pair reserves
    function _univ2_getTokenPrice_0(address pairAddress, uint256 amount) internal view returns(uint256)
    {
        IUniswapV2Pair_Like pair = IUniswapV2Pair_Like(pairAddress);
        //ERC20 token1 = ERC20(pair.token1());
        (uint Res0, uint Res1,) = pair.getReserves();

        // decimals
        //uint res0 = Res0*(10**token1.decimals());
        uint256 ret = ((amount*Res0)/Res1); // return amount of token0 needed to buy token1

        return _sync_usdprice_decimals8(ret, ERC20(pair.token0()).decimals());
    }
    function _univ2_getTokenPrice_1(address pairAddress, uint amount) internal view returns(uint256)
    {
        IUniswapV2Pair_Like pair = IUniswapV2Pair_Like(pairAddress);
        //ERC20 token0 = ERC20(pair.token0());
        (uint Res0, uint Res1,) = pair.getReserves();

        // decimals
        //uint res1 = Res1*(10**token0.decimals());
        uint256 ret = ((amount*Res1)/Res0); // return amount of token1 needed to buy token0
        
        return _sync_usdprice_decimals8(ret, ERC20(pair.token1()).decimals());
    }

    // uniswap v2 get token price ---------------------------------------------
    // calculate price based on pair reserves
    function _univ3_getTokenPrice_0(address pairAddress, uint amount) public view returns (uint256) {
        IUniswapV3Pool_Like pool = IUniswapV3Pool_Like(pairAddress);
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();

        uint256 Res0 = pool.liquidity() * Q96 / sqrtPriceX96;
        uint256 Res1 = pool.liquidity() * sqrtPriceX96 / Q96;

        uint256 ret = (amount*Res0) / Res1;
        
        return _sync_usdprice_decimals8(ret, ERC20(pool.token0()).decimals());
    }
    function _univ3_getTokenPrice_1(address pairAddress, uint amount) public view returns (uint256) {
        IUniswapV3Pool_Like pool = IUniswapV3Pool_Like(pairAddress);
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();

        uint256 Res0 = pool.liquidity() * Q96 / sqrtPriceX96;
        uint256 Res1 = pool.liquidity() * sqrtPriceX96 / Q96;

        uint256 ret = (amount*Res1) / Res0;
        
        return _sync_usdprice_decimals8(ret, ERC20(pool.token1()).decimals());
    }
}
