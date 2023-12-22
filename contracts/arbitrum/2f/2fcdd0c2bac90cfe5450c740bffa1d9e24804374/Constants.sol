// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library Constants {
    /// @dev ArbiturmOne & Goerli uniswap V3
    address public constant UNISWAP_V3_FACTORY_ADDRESS =
        address(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    address public constant NONFUNGIBLE_POSITION_MANAGER_ADDRESS =
        address(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    address public constant SWAP_ROUTER_ADDRESS =
        address(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    /// @dev ArbiturmOne token address
    address public constant WETH_ADDRESS =
        address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address public constant ARB_ADDRESS =
        address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    address public constant WBTC_ADDRESS =
        address(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    address public constant USDC_ADDRESS =
        address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    address public constant USDCE_ADDRESS =
        address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    address public constant USDT_ADDRESS =
        address(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    address public constant RDNT_ADDRESS =
        address(0x3082CC23568eA640225c2467653dB90e9250AaA0);
    address public constant LINK_ADDRESS =
        address(0xf97f4df75117a78c1A5a0DBb814Af92458539FB4);

    /// @dev black hole address
    address public constant BLACK_HOLE_ADDRESS =
        address(0x000000000000000000000000000000000000dEaD);
}

