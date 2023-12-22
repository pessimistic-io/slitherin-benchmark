// SPDX-License-Identifier: GPL-3.0-or-later

/*
 //======================================================================\\
 //======================================================================\\
  *******         **********     ***********     *****     ***********
  *      *        *              *                 *       *
  *        *      *              *                 *       *
  *         *     *              *                 *       *
  *         *     *              *                 *       *
  *         *     **********     *       *****     *       ***********
  *         *     *              *         *       *                 *
  *         *     *              *         *       *                 *
  *        *      *              *         *       *                 *
  *      *        *              *         *       *                 *
  *******         **********     ***********     *****     ***********
 \\======================================================================//
 \\======================================================================//
*/

import "./OwnableWithoutContextUpgradeable.sol";

import "./ISwapRouter.sol";
import "./ILBRouter.sol";

pragma solidity ^0.8.13;

contract SwapHelper is OwnableWithoutContextUpgradeable {
    // Swap USDC to get protocol native tokens
    address public constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address public constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    // Uniswap V3
    address public constant GMX = 0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a;
    address public constant GNS = 0x18c11FD286C5EC11c3b683Caa813B77f5163A122;
    address public constant WOM = 0x7B5EB3940021Ec0e8e463D5dBB4B7B09a89DDF96;
    address public constant LDO = 0x13Ad51ed4F1B7e9Dc168d8a00cB3f4dDD85EfA60;
    address public constant ARB = 0x912CE59144191C1204E64559FE8253a0e49E6548;

    // TraderJoe Liquidity Book V2_1
    address public constant JOE = 0x371c7ec6D8039ff7933a2AA28EB827Ffe1F52f07;

    address public constant UNIV3_ROUTER =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public constant JOEV21_ROUTER =
        0xb4315e873dBcf96Ffd0acd8EA43f689D8c20fB30;

    // Fee rate in Uniswap V3
    uint256 public constant WETH_USDC_FEE = 500; // 0.05%
    uint256 public constant WETH_USDT_FEE = 500; // 0.05%

    uint256 public constant WOM_USDT_FEE = 3000;

    uint256 public constant GMX_WETH_FEE = 3000;
    uint256 public constant GNS_WETH_FEE = 3000;
    uint256 public constant LDO_WETH_FEE = 3000;
    uint256 public constant ARB_WETH_FEE = 500;

    // Router types:
    // 1: Uniswap V3
    // 2: Trader Joe V2.1
    mapping(address => uint256) public routerTypes;

    // Pool fees for those tokens that uses Uniswap V3
    // The pair may be token-USDC or token-USDT or token-WETH
    mapping(address => uint256) public poolFees;

    function initialize() public initializer {
        __Ownable_init();

        routerTypes[GMX] = 1;
        routerTypes[GNS] = 1;
        routerTypes[WOM] = 1;
        routerTypes[LDO] = 1;
        routerTypes[ARB] = 1;

        routerTypes[JOE] = 2;
    }

    function setRouterType(address _token, uint256 _type) external onlyOwner {
        routerTypes[_token] = _type;
    }

    function swap(address _token, uint256 _amount) external returns (uint256) {
        uint256 routerType = routerTypes[_token];

        if (routerType == 1) {
            return _univ3_swapExactTokensForTokens(_token, _amount);
        } else if (routerType == 2) {
            return _joev21_swapExactTokensForTokens(_token, _amount);
        } else revert("Wrong token");
    }

    function _univ3_swapExactTokensForTokens(
        address _token,
        uint256 _amount
    ) internal returns (uint256 amountOut) {
        if (
            IERC20(_token).allowance(address(this), UNIV3_ROUTER) < 1000000e18
        ) {
            IERC20(_token).approve(UNIV3_ROUTER, type(uint256).max);
        }

        bytes memory path = getUniV3Path(_token);

        ISwapRouter.ExactInputParams memory params = ISwapRouter
            .ExactInputParams({
                path: path,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: _amount,
                amountOutMinimum: 0
            });

        amountOut = ISwapRouter(UNIV3_ROUTER).exactInput(params);
    }

    function _getPairBinSteps(
        address _token
    ) internal pure returns (uint256[] memory pairBinSteps) {
        pairBinSteps = new uint256[](2);

        if (_token == JOE) {
            pairBinSteps[0] = 20; // JOE-ETH pair: 0x4b9bfeD1dD4E6780454b2B02213788f31FfBA74a 20bps V2_1
            pairBinSteps[1] = 50; // ETH-USDC pair: 0xb83783c9cb35f1b1A6338937F9BE3EBb36b46bfe 40bps V2_1
        } else revert("Wrong token");
    }

    function _getVersions(
        address _token
    ) internal pure returns (ILBRouter.Version[] memory versions) {
        versions = new ILBRouter.Version[](2);

        if (_token == JOE) {
            versions[0] = ILBRouter.Version.V2_1;
            versions[1] = ILBRouter.Version.V2_1;
        }
    }

    function _joev21_swapExactTokensForTokens(
        address _token,
        uint256 _amount
    ) internal returns (uint256 amountOut) {
        if (
            IERC20(_token).allowance(address(this), JOEV21_ROUTER) < 1000000e18
        ) {
            IERC20(_token).approve(JOEV21_ROUTER, type(uint256).max);
        }

        uint256[] memory pairBinSteps = _getPairBinSteps(_token);

        ILBRouter.Version[] memory versions = _getVersions(_token);

        IERC20[] memory tokenPath = new IERC20[](3);
        tokenPath[0] = IERC20(_token);
        tokenPath[1] = IERC20(WETH);
        tokenPath[2] = IERC20(USDC);

        ILBRouter.Path memory path = ILBRouter.Path({
            pairBinSteps: pairBinSteps,
            versions: versions,
            tokenPath: tokenPath
        });

        amountOut = ILBRouter(JOEV21_ROUTER).swapExactTokensForTokens(
            _amount,
            0,
            path,
            msg.sender,
            block.timestamp + 1
        );
    }

    function getUniV3Path(
        address _token
    ) public pure returns (bytes memory path) {
        if (_token == WOM) {
            path = abi.encodePacked(
                WOM,
                WOM_USDT_FEE,
                USDT,
                WETH_USDT_FEE,
                USDT
            );
        } else if (_token == GMX) {
            path = abi.encodePacked(
                GMX,
                GMX_WETH_FEE,
                WETH,
                WETH_USDC_FEE,
                USDC
            );
        } else if (_token == GNS) {
            path = abi.encodePacked(
                GNS,
                GNS_WETH_FEE,
                WETH,
                WETH_USDC_FEE,
                USDC
            );
        } else if (_token == LDO) {
            path = abi.encodePacked(
                LDO,
                LDO_WETH_FEE,
                WETH,
                WETH_USDC_FEE,
                USDC
            );
        } else if (_token == ARB) {
            path = abi.encodePacked(
                ARB,
                ARB_WETH_FEE,
                WETH,
                WETH_USDC_FEE,
                USDC
            );
        } else revert("Wrong token");
    }
}

