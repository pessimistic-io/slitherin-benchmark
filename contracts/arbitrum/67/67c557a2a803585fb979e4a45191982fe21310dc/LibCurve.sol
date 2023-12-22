// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {AppStorage, LibMagpieRouter} from "./LibMagpieRouter.sol";
import {LibAsset} from "./LibAsset.sol";
import {ICryptoFactory} from "./ICryptoFactory.sol";
import {ICryptoPool} from "./kokonut-swap_ICryptoPool.sol";
import {ICryptoRegistry} from "./ICryptoRegistry.sol";
import {ICurvePool} from "./ICurvePool.sol";
import {IRegistry} from "./kokonut-swap_IRegistry.sol";
import {Hop} from "./LibHop.sol";

struct ExchangeArgs {
    address pool;
    address from;
    address to;
    uint256 amount;
}

library LibCurve {
    using LibAsset for address;

    function getPoolAddress(bytes memory poolData) private pure returns (address poolAddress) {
        assembly {
            poolAddress := shr(96, mload(add(poolData, 32)))
        }
    }

    function mainExchange(ExchangeArgs memory exchangeArgs, address registry) private {
        int128 i = 0;
        int128 j = 0;
        bool isUnderlying = false;
        (i, j, isUnderlying) = IRegistry(registry).get_coin_indices(
            exchangeArgs.pool,
            exchangeArgs.from,
            exchangeArgs.to
        );

        if (isUnderlying) {
            ICurvePool(exchangeArgs.pool).exchange_underlying(i, j, exchangeArgs.amount, 0);
        } else {
            ICurvePool(exchangeArgs.pool).exchange(i, j, exchangeArgs.amount, 0);
        }
    }

    function cryptoExchange(ExchangeArgs memory exchangeArgs, address registry) private {
        uint256 i = 0;
        uint256 j = 0;
        address initial = exchangeArgs.from;
        address target = exchangeArgs.to;

        (i, j) = ICryptoRegistry(registry).get_coin_indices(exchangeArgs.pool, initial, target);

        ICryptoPool(exchangeArgs.pool).exchange(i, j, exchangeArgs.amount, 0);
    }

    function swapCurve(Hop memory h) internal returns (uint256 amountOut) {
        AppStorage storage s = LibMagpieRouter.getStorage();

        uint256 i;
        uint256 l = h.path.length;

        for (i = 0; i < l - 1; ) {
            address pool = getPoolAddress(h.poolDataList[i]);

            ExchangeArgs memory exchangeArgs = ExchangeArgs({
                pool: pool,
                from: h.path[i],
                to: h.path[i + 1],
                amount: i == 0 ? h.amountIn : amountOut
            });

            h.path[i].approve(exchangeArgs.pool, h.amountIn);

            if (
                s.curveSettings.cryptoRegistry != address(0) &&
                ICryptoRegistry(s.curveSettings.cryptoRegistry).get_n_coins(exchangeArgs.pool) > 0
            ) {
                cryptoExchange(exchangeArgs, s.curveSettings.cryptoRegistry);
            } else if (
                s.curveSettings.mainRegistry != address(0) &&
                IRegistry(s.curveSettings.mainRegistry).get_n_coins(exchangeArgs.pool)[0] > 0
            ) {
                mainExchange(exchangeArgs, s.curveSettings.mainRegistry);
            } else if (s.curveSettings.cryptoFactory != address(0)) {
                cryptoExchange(exchangeArgs, s.curveSettings.cryptoFactory);
            }

            amountOut = h.path[i + 1].getBalance();

            unchecked {
                i++;
            }
        }
    }
}

