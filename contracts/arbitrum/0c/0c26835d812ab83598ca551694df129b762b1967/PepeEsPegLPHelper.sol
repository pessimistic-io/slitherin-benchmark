//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Ownable } from "./Ownable.sol";
import { ERC20 } from "./ERC20.sol";
import { IERC20 } from "./IERC20.sol";
import { IWeightedPoolFactory, IWeightedPool, IAsset, IVault } from "./IWeightedPoolFactory.sol";
import { IPepeLockUp } from "./IPepeLockUp.sol";

abstract contract PepeEsPegLPHelper {
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant PEG = 0x4fc2A3Fb655847b7B72E19EAA2F10fDB5C2aDdbe;
    address public constant VAULT_ADDRESS = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public constant LP_TOKEN = 0x3eFd3E18504dC213188Ed2b694F886A305a6e5ed;
    bytes32 public constant POOL_ID = 0x3efd3e18504dc213188ed2b694f886a305a6e5ed00020000000000000000041d;

    event AddedLP(uint256 wethAmount, uint256 pegAmount, uint256 minBlpOut);

    function _joinPool(uint256 wethAmount, uint256 pegAmount, uint256 minBlpOut) internal {
        (address token0, address token1) = sortTokens(PEG, WETH);
        IAsset[] memory assets = new IAsset[](2);
        assets[0] = IAsset(token0);
        assets[1] = IAsset(token1);

        uint256[] memory maxAmountsIn = new uint256[](2);
        if (token0 == WETH) {
            maxAmountsIn[0] = wethAmount;
            maxAmountsIn[1] = pegAmount;
        } else {
            maxAmountsIn[0] = pegAmount;
            maxAmountsIn[1] = wethAmount;
        }

        IERC20(PEG).approve(VAULT_ADDRESS, pegAmount);
        IERC20(WETH).approve(VAULT_ADDRESS, wethAmount);

        bytes memory userDataEncoded = abi.encode(
            IWeightedPool.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
            maxAmountsIn,
            minBlpOut
        );
        IVault.JoinPoolRequest memory inRequest = IVault.JoinPoolRequest(assets, maxAmountsIn, userDataEncoded, false);
        IVault(VAULT_ADDRESS).joinPool(POOL_ID, address(this), address(this), inRequest);

        emit AddedLP(wethAmount, pegAmount, minBlpOut);
    }

    function _exitPool(uint256 lpAmount) internal {
        (address token0, address token1) = sortTokens(PEG, WETH);
        IAsset[] memory assets = new IAsset[](2);
        assets[0] = IAsset(token0);
        assets[1] = IAsset(token1);

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 1;
        minAmountsOut[1] = 1;

        IERC20(LP_TOKEN).approve(VAULT_ADDRESS, lpAmount);

        bytes memory userData = abi.encode(IWeightedPool.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT, lpAmount);

        IVault.ExitPoolRequest memory request = IVault.ExitPoolRequest(assets, minAmountsOut, userData, false);
        IVault(VAULT_ADDRESS).exitPool(POOL_ID, address(this), payable(msg.sender), request); //send both peg and weth to the locker (user).
    }

    function sortTokens(address tokenA, address tokenB) public pure returns (address token0, address token1) {
        require(tokenA != tokenB, "IDENTICAL_ADDRESSES");
        require(tokenA != address(0), "ZERO_ADDRESS");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }
}

