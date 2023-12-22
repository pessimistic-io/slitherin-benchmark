// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {AppStorage, LibMagpieRouter} from "./LibMagpieRouter.sol";
import {LibAsset} from "./LibAsset.sol";
import {ICryptoFactory} from "./ICryptoFactory.sol";
import {ICryptoRegistry} from "./ICryptoRegistry.sol";
import {IRegistry} from "./IRegistry.sol";
import {Hop} from "./LibHop.sol";

error InvalidProtocol();
error InvalidAddLiquidityCall();
error InvalidRemoveLiquidityCall();
error InvalidTokenIndex();

library LibCurveLp {
    using LibAsset for address;

    function getTokenIndex2(address tokenAddress, address[2] memory tokenAddresses) internal pure returns (uint256) {
        uint256 l = tokenAddresses.length;
        for (uint256 i = 0; i < l; ) {
            if (tokenAddresses[i] == tokenAddress) {
                return i;
            }

            unchecked {
                i++;
            }
        }

        revert InvalidTokenIndex();
    }

    function getTokenIndex8(address tokenAddress, address[8] memory tokenAddresses) internal pure returns (uint256) {
        uint256 l = tokenAddresses.length;
        for (uint256 i = 0; i < l; ) {
            if (tokenAddresses[i] == tokenAddress) {
                return i;
            }

            unchecked {
                i++;
            }
        }

        revert InvalidTokenIndex();
    }

    function addLiquidity(uint256 tokenCount, uint256 tokenIndex, address poolAddress, uint256 amountIn) internal {
        bytes memory signature;

        if (tokenCount == 2) {
            uint256[2] memory amountIns = [uint256(0), uint256(0)];
            amountIns[tokenIndex] = amountIn;
            signature = abi.encodeWithSignature("add_liquidity(uint256[2],uint256)", amountIns, 0);
        } else if (tokenCount == 3) {
            uint256[3] memory amountIns = [uint256(0), uint256(0), uint256(0)];
            amountIns[tokenIndex] = amountIn;
            signature = abi.encodeWithSignature("add_liquidity(uint256[3],uint256)", amountIns, 0);
        } else if (tokenCount == 4) {
            uint256[4] memory amountIns = [uint256(0), uint256(0), uint256(0), uint256(0)];
            amountIns[tokenIndex] = amountIn;
            signature = abi.encodeWithSignature("add_liquidity(uint256[4],uint256)", amountIns, 0);
        } else if (tokenCount == 5) {
            uint256[5] memory amountIns = [uint256(0), uint256(0), uint256(0), uint256(0), uint256(0)];
            amountIns[tokenIndex] = amountIn;
            signature = abi.encodeWithSignature("add_liquidity(uint256[5],uint256)", amountIns, 0);
        } else if (tokenCount == 6) {
            uint256[6] memory amountIns = [uint256(0), uint256(0), uint256(0), uint256(0), uint256(0), uint256(0)];
            amountIns[tokenIndex] = amountIn;
            signature = abi.encodeWithSignature("add_liquidity(uint256[6],uint256)", amountIns, 0);
        } else if (tokenCount == 7) {
            uint256[7] memory amountIns = [
                uint256(0),
                uint256(0),
                uint256(0),
                uint256(0),
                uint256(0),
                uint256(0),
                uint256(0)
            ];
            amountIns[tokenIndex] = amountIn;
            signature = abi.encodeWithSignature("add_liquidity(uint256[7],uint256)", amountIns, 0);
        } else if (tokenCount == 8) {
            uint256[8] memory amountIns = [
                uint256(0),
                uint256(0),
                uint256(0),
                uint256(0),
                uint256(0),
                uint256(0),
                uint256(0),
                uint256(0)
            ];
            amountIns[tokenIndex] = amountIn;
            signature = abi.encodeWithSignature("add_liquidity(uint256[8],uint256)", amountIns, 0);
        }

        (bool success, ) = poolAddress.call(signature);
        if (!success) {
            revert InvalidAddLiquidityCall();
        }
    }

    function removeLiquidityMain(uint256 tokenIndex, address poolAddress, uint256 amountIn) internal {
        (bool success, ) = poolAddress.call(
            abi.encodeWithSignature(
                "remove_liquidity_one_coin(uint256,int128,uint256)",
                amountIn,
                int128(int256(tokenIndex)),
                0
            )
        );
        if (!success) {
            revert InvalidRemoveLiquidityCall();
        }
    }

    function removeLiquidityCrypto(uint256 tokenIndex, address poolAddress, uint256 amountIn) internal {
        (bool success, ) = poolAddress.call(
            abi.encodeWithSignature("remove_liquidity_one_coin(uint256,uint256,uint256)", amountIn, tokenIndex, 0)
        );
        if (!success) {
            revert InvalidRemoveLiquidityCall();
        }
    }

    function swapCrypto(
        address poolAddress,
        uint256 amountIn,
        address tokenAddress,
        bool isDeposit
    ) internal returns (bool) {
        AppStorage storage s = LibMagpieRouter.getStorage();

        uint256 tokenCount = ICryptoRegistry(s.curveSettings.cryptoRegistry).get_n_coins(poolAddress);

        if (s.curveSettings.cryptoRegistry != address(0) && tokenCount > 1) {
            uint256 tokenIndex = getTokenIndex8(
                tokenAddress,
                ICryptoRegistry(s.curveSettings.cryptoRegistry).get_coins(poolAddress)
            );
            if (isDeposit) {
                addLiquidity(tokenCount, tokenIndex, poolAddress, amountIn);
            } else {
                removeLiquidityCrypto(tokenIndex, poolAddress, amountIn);
            }

            return true;
        }

        return false;
    }

    function swapFactory(
        address poolAddress,
        uint256 amountIn,
        address tokenAddress,
        bool isDeposit
    ) internal returns (bool) {
        AppStorage storage s = LibMagpieRouter.getStorage();

        uint256 tokenCount = 2;

        if (s.curveSettings.cryptoFactory != address(0)) {
            uint256 tokenIndex = getTokenIndex2(
                tokenAddress,
                ICryptoFactory(s.curveSettings.cryptoFactory).get_coins(poolAddress)
            );

            if (isDeposit) {
                addLiquidity(tokenCount, tokenIndex, poolAddress, amountIn);
            } else {
                removeLiquidityCrypto(tokenIndex, poolAddress, amountIn);
            }

            return true;
        }

        return false;
    }

    function swapMain(
        address poolAddress,
        uint256 amountIn,
        address tokenAddress,
        bool isDeposit
    ) internal returns (bool) {
        AppStorage storage s = LibMagpieRouter.getStorage();

        uint256 tokenCount = IRegistry(s.curveSettings.mainRegistry).get_n_coins(poolAddress)[0];

        if (tokenCount > 1) {
            uint256 tokenIndex = getTokenIndex8(
                tokenAddress,
                IRegistry(s.curveSettings.mainRegistry).get_coins(poolAddress)
            );

            if (isDeposit) {
                addLiquidity(tokenCount, tokenIndex, poolAddress, amountIn);
            } else {
                removeLiquidityMain(tokenIndex, poolAddress, amountIn);
            }

            return true;
        }

        return false;
    }

    function swapCurveLp(Hop memory h) internal returns (uint256 amountOut) {
        uint256 i;
        uint256 l = h.path.length;

        for (i = 0; i < l - 1; ) {
            bytes memory poolData = h.poolDataList[i];
            uint8 operation;
            address poolAddress;
            assembly {
                operation := shr(248, mload(add(poolData, 32)))
                poolAddress := shr(96, mload(add(poolData, 33)))
            }
            uint256 amountIn = i == 0 ? h.amountIn : amountOut;
            address fromAddress = h.path[i];
            address toAddress = h.path[i + 1];
            bool isDeposit = operation == 1;
            address tokenAddress = isDeposit ? fromAddress : toAddress;

            if (isDeposit) {
                fromAddress.approve(poolAddress, h.amountIn);
            }

            if (!swapCrypto(poolAddress, amountIn, tokenAddress, isDeposit)) {
                if (!swapMain(poolAddress, amountIn, tokenAddress, isDeposit)) {
                    if (!swapFactory(poolAddress, amountIn, tokenAddress, isDeposit)) {
                        revert InvalidProtocol();
                    }
                }
            }

            amountOut = toAddress.getBalance();

            unchecked {
                i++;
            }
        }
    }
}

