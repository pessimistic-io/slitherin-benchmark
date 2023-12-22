// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20, ERC20} from "./ERC20.sol";

import {SafeERC20} from "./SafeERC20.sol";
import { SafeMath } from "./SafeMath.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {Initializable} from "./Initializable.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";

import {ICamelotPair} from "./ICamelotPair.sol";
import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";
import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {ICamelotRouter} from "./ICamelotRouter.sol";
import {ILBQuoter} from "./ILBQuoter.sol";

/// @title MagpieReader for Arbitrum
/// @author Magpie Team

contract PenpieReader is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    struct TokenPrice {
        address token;
        string  symbol;
        uint256 price;
    }

    struct TokenRouter {
        address token;
        string symbol;
        uint256 decimals;
        address[] paths;
        address[] pools;
        address chainlink;
        uint256 routerType;
    }

    /* ============ State Variables ============ */

    mapping(address => TokenRouter) public tokenRouterMap;
    address[] public tokenList;

    uint256 constant CamelotRouterType = 1;
    uint256 constant WombatRouterType = 2;
    uint256 constant ChainlinkType = 3;
    uint256 constant UniswapV3RouterType = 4;
    uint256 constant TraderJoeV2Type = 5;
    
    address constant public TraderJoeV2LBQuoter = 0x7f281f22eDB332807A039073a7F34A4A215bE89e;
    ICamelotRouter constant public CamelotRouter = ICamelotRouter(0xc873fEcbd354f5A56E00E710B90EF4201db2448d);
    address constant public WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    /* ============ Events ============ */

    /* ============ Errors ============ */

    /* ============ Constructor ============ */

    function __PenpieReader_init() public initializer {
        __Ownable_init();
    }

    /* ============ External Getters ============ */

    // function getUSDTPrice() public view returns (uint256) {
    //     return getTokenPrice(USDT, address(0));
    // }

    // function getUSDCPrice() public view returns (uint256) {
    //     return getTokenPrice(USDC, address(0));
    // }    

    function getWETHPrice() public view returns (uint256) {
        return getTokenPrice(WETH, address(0));
    }

    // just to make frontend happy
    function getETHPrice() public view returns (uint256) {
        return getTokenPrice(WETH, address(0));
    }

    function getTokenPrice(address token, address unitToken) public view returns (uint256) {
        TokenRouter memory tokenRouter = tokenRouterMap[token];
        uint256 amountOut = 0;
        if (tokenRouter.token != address(0)) {
           if (tokenRouter.routerType == CamelotRouterType) {
            uint256[] memory prices = CamelotRouter.getAmountsOut(10 ** tokenRouter.decimals , tokenRouter.paths);
            amountOut = prices[tokenRouter.paths.length - 1];
           }
           else if (tokenRouter.routerType == ChainlinkType) {
            AggregatorV3Interface aggregatorV3Interface = AggregatorV3Interface(tokenRouter.chainlink);
              (
                /* uint80 roundID */,
                int256 price,
                /*uint startedAt*/,
                /*uint timeStamp*/,
                /*uint80 answeredInRound*/
            ) = aggregatorV3Interface.latestRoundData();
            amountOut = uint256(price * 1e18 / 1e8);
           } else if (tokenRouter.routerType == UniswapV3RouterType) {
            IUniswapV3Pool pool = IUniswapV3Pool(tokenRouter.pools[0]);
            (uint160 sqrtPriceX96,,,,,,) =  pool.slot0();
            amountOut = uint(sqrtPriceX96) * (uint(sqrtPriceX96)) * (1e18) >> (96 * 2);
           } else if (tokenRouter.routerType == TraderJoeV2Type) {
            uint256[] memory quotes = (ILBQuoter(TraderJoeV2LBQuoter).findBestPathFromAmountIn(tokenRouter.paths, 10 ** tokenRouter.decimals)).amounts;
            amountOut = quotes[tokenRouter.paths.length - 1];
           }
       
        }
        if (unitToken == address(0)) {
            return amountOut;
        } 

        TokenRouter memory router = tokenRouterMap[unitToken];
        uint256 unitPrice;
        if (router.routerType != ChainlinkType) {
            address target = router.paths[router.paths.length - 1];
            unitPrice = getTokenPrice(unitToken, target);
        } else {
            unitPrice = getTokenPrice(unitToken, address(0));
        }
        
        uint256 uintDecimals =  ERC20(unitToken).decimals();
        return amountOut * unitPrice / (10 ** uintDecimals);
    }

    function getAllTokenPrice() public view returns (TokenPrice[] memory) {
        TokenPrice[] memory items = new TokenPrice[](tokenList.length);
        for(uint256 i = 0; i < tokenList.length; i++) {
            TokenPrice memory tokenPrice;
            TokenRouter memory router = tokenRouterMap[tokenList[i]];
            address target;

            if (router.routerType != ChainlinkType) {
                target = router.paths[router.paths.length - 1];

            }

            tokenPrice.price = getTokenPrice(tokenList[i], target);
            
            tokenPrice.symbol = router.symbol;
            tokenPrice.token = tokenList[i];
            items[i] = tokenPrice;
        }
        return items;
    }

    /* ============ Internal Functions ============ */

    function _addTokenRouteInteral(address tokenAddress, address [] memory paths, address[] memory pools) internal returns (TokenRouter memory tokenRouter) {
        if (tokenRouterMap[tokenAddress].token == address(0)) {
            tokenList.push(tokenAddress);
        }
        tokenRouter.token = tokenAddress;
        tokenRouter.symbol = ERC20(tokenAddress).symbol();
        tokenRouter.decimals = ERC20(tokenAddress).decimals();
        tokenRouter.paths = paths;
        tokenRouter.pools = pools;
    }

    /* ============ Admin Functions ============ */

    function addTokenCamelotRouter(address tokenAddress, address [] memory paths, address[] memory pools) external onlyOwner  {
        TokenRouter memory tokenRouter = _addTokenRouteInteral(tokenAddress, paths, pools);
        tokenRouter.routerType = CamelotRouterType;
        tokenRouterMap[tokenAddress] = tokenRouter;
    }

    function addUniswapV3Router(address tokenAddress, address [] memory paths, address[] memory pools) external onlyOwner  {
        TokenRouter memory tokenRouter = _addTokenRouteInteral(tokenAddress, paths, pools);
        tokenRouter.routerType = UniswapV3RouterType;
        tokenRouterMap[tokenAddress] = tokenRouter;
    }

    function addTradeJoeV2Router(address tokenAddress, address [] memory paths, address[] memory pools) external onlyOwner  {
        TokenRouter memory tokenRouter = _addTokenRouteInteral(tokenAddress, paths, pools);
        tokenRouter.routerType = TraderJoeV2Type;
        tokenRouterMap[tokenAddress] = tokenRouter;
    }        

    function addTokenChainlink(address tokenAddress, address [] memory paths, address[] memory pools, address priceAddress) external onlyOwner  {
        TokenRouter memory tokenRouter = _addTokenRouteInteral(tokenAddress, paths, pools);
        tokenRouter.routerType = ChainlinkType;
        tokenRouter.chainlink = priceAddress;
        tokenRouterMap[tokenAddress] = tokenRouter;
    }
}
