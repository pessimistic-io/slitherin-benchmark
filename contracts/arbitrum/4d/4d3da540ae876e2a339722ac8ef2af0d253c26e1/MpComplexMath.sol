// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
// It's deserved to be called complex
// Tons of hours to make it work
// Never underestimate multipool maths or it will destroy you...
// Enjoy P.S BadConfig

import "./ERC20.sol";
import "./Ownable.sol";
import {SD59x18, sd} from "./SD59x18.sol";
import {MpAsset, MpContext} from "./Multipool.sol";

uint constant DENOMINATOR = 1e18;

library MpComplexMath {
    struct MpAssetSigned {
        SD59x18 quantity;
        SD59x18 price;
        SD59x18 collectedFees;
        SD59x18 collectedCashbacks;
        SD59x18 share;
    }

    struct MpContextSigned {
        SD59x18 usdCap;
        SD59x18 totalTargetShares;
        SD59x18 halfDeviationFee;
        SD59x18 deviationLimit;
        SD59x18 operationBaseFee;
        SD59x18 userCashbackBalance;
        SD59x18 depegBaseFee;
    }

    function sign(MpContext memory c) internal pure returns (MpContextSigned memory) {
        return MpContextSigned({
            usdCap: sign(c.usdCap),
            totalTargetShares: sign(c.totalTargetShares),
            halfDeviationFee: sign(c.halfDeviationFee),
            deviationLimit: sign(c.deviationLimit),
            operationBaseFee: sign(c.operationBaseFee),
            userCashbackBalance: sign(c.userCashbackBalance),
            depegBaseFee: sign(c.depegBaseFee)
        });
    }

    function sign(MpAsset memory asset) internal pure returns (MpAssetSigned memory) {
        return MpAssetSigned({
            quantity: sign(asset.quantity),
            price: sign(asset.price),
            collectedFees: sign(asset.collectedFees),
            collectedCashbacks: sign(asset.collectedCashbacks),
            share: sign(asset.share)
        });
    }

    function sign(uint a) internal pure returns (SD59x18 b) {
        b = sd(int(a));
    }

    function unsign(SD59x18 a) internal pure returns (uint b) {
        b = uint(a.unwrap());
    }

    function mintRev(MpContext memory context, MpAsset memory asset, uint utilisableQuantity)
        internal
        view
        returns (uint suppliedQuantity)
    {
        suppliedQuantity = context.evalMint(asset, utilisableQuantity);
    }

    function burn(MpContext memory context, MpAsset memory asset, uint suppliedQuantity)
        internal
        pure
        returns (uint utilisableQuantity)
    {
        utilisableQuantity = context.evalBurn(asset, suppliedQuantity);
    }

    function calculateDeviationMint(MpContext memory context, MpAsset memory asset, uint utilisableQuantity)
        internal
        pure
        returns (uint deviation)
    {
        SD59x18 share = sign(
            ((asset.quantity + utilisableQuantity) * asset.price)
                / (context.usdCap + utilisableQuantity * asset.price / DENOMINATOR)
        );
        SD59x18 targetShare = sign(asset.share * DENOMINATOR / context.totalTargetShares);
        deviation = unsign((share - targetShare).abs());
    }

    function calculateDeviationBurn(MpContext memory context, MpAsset memory asset, uint suppliedQuantity)
        internal
        pure
        returns (uint deviation)
    {
        SD59x18 share = sign(
            ((asset.quantity - suppliedQuantity) * asset.price)
                / (context.usdCap - suppliedQuantity * asset.price / DENOMINATOR)
        );
        SD59x18 targetShare = sign(asset.share * DENOMINATOR / context.totalTargetShares);
        deviation = unsign((share - targetShare).abs());
    }

    function calculateDeviationBurnTrace(
        MpContext memory context,
        MpAsset memory asset,
        uint suppliedQuantity,
        uint mintQuantity,
        uint mintPrice
    ) internal pure returns (uint deviation) {
        SD59x18 share = sign(
            ((asset.quantity - suppliedQuantity) * asset.price)
                / (context.usdCap + mintQuantity * mintPrice / DENOMINATOR - suppliedQuantity * asset.price / DENOMINATOR)
        );
        SD59x18 targetShare = sign(asset.share * DENOMINATOR / context.totalTargetShares);
        deviation = unsign((share - targetShare).abs());
    }

    function burnRev(MpContext memory context, MpAsset memory asset, uint utilisableQuantity)
        internal
        pure
        returns (uint suppliedQuantity)
    {
        require(utilisableQuantity <= asset.quantity, "MULTIPOOL: QE");

        uint withFees = unsign(getSuppliableBurnQuantity(sign(utilisableQuantity), sign(context), sign(asset)));
        uint noFees = utilisableQuantity * (1e18 + context.operationBaseFee) / DENOMINATOR;

        uint deviationWithFees = calculateDeviationBurn(context, asset, withFees);
        uint deviationNoFees = calculateDeviationBurn(context, asset, noFees);
        uint deviationOld = calculateDeviationBurn(context, asset, 0);

        if (deviationNoFees <= deviationOld) {
            suppliedQuantity = noFees;
            require(suppliedQuantity <= asset.quantity, "MULTIPOOL: QE");

            uint cashback;
            if (deviationOld != 0) {
                cashback = (asset.collectedCashbacks * (deviationOld - deviationNoFees)) / deviationOld;
            }

            asset.collectedCashbacks = asset.collectedCashbacks - cashback;
            context.userCashbackBalance = context.userCashbackBalance + cashback;
        } else {
            suppliedQuantity = withFees;
            require(suppliedQuantity <= asset.quantity, "MULTIPOOL: QE");
            require(deviationWithFees < context.deviationLimit, "MULTIPOOL: DO");
            require(withFees != 0, "MULTIPOOL: CF");

            uint _operationBaseFee = context.operationBaseFee;
            uint collectedCashbacks = suppliedQuantity - utilisableQuantity * (1e18 + _operationBaseFee) / DENOMINATOR;
            uint collectedBaseDepegFee = (collectedCashbacks * context.depegBaseFee) / DENOMINATOR;
            asset.collectedCashbacks = asset.collectedCashbacks + collectedCashbacks - collectedBaseDepegFee;
            asset.collectedFees = asset.collectedFees + collectedBaseDepegFee;
        }

        asset.quantity = asset.quantity - suppliedQuantity;
        context.usdCap = context.usdCap - suppliedQuantity * asset.price / DENOMINATOR;
        asset.collectedFees = asset.collectedFees + utilisableQuantity * context.operationBaseFee / DENOMINATOR;
    }

    function mint(MpContext memory context, MpAsset memory asset, uint suppliedQuantity)
        internal
        pure
        returns (uint utilisableQuantity)
    {
        if (context.usdCap == 0) {
            context.usdCap = suppliedQuantity * asset.price / DENOMINATOR;
            asset.quantity = asset.quantity + suppliedQuantity;
            return suppliedQuantity;
        }
        uint withFees = unsign(getUtilisableMintQuantity(sign(suppliedQuantity), sign(context), sign(asset)));
        uint noFees = suppliedQuantity * DENOMINATOR / (1e18 + context.operationBaseFee);

        uint deviationWithFees = calculateDeviationMint(context, asset, withFees);
        uint deviationNoFees = calculateDeviationMint(context, asset, noFees);
        uint deviationOld = calculateDeviationMint(context, asset, 0);

        if (deviationNoFees <= deviationOld) {
            utilisableQuantity = noFees;

            if (deviationOld != 0) {
                uint cashback = (asset.collectedCashbacks * (deviationOld - deviationNoFees)) / deviationOld;
                asset.collectedCashbacks = asset.collectedCashbacks - cashback;
                context.userCashbackBalance = context.userCashbackBalance + cashback;
            }
        } else {
            require(deviationWithFees < context.deviationLimit, "MULTIPOOL: DO");
            require(withFees != 0, "MULTIPOOL: CF");

            utilisableQuantity = withFees;
            // straightforward form but seems like it is not so good in accuracy,
            // base fee is easy to compute bc of one multiplication so to keep
            // deviation fee + base fee + utilisable val = supplied val
            // we use substraction here
            uint _operationBaseFee = context.operationBaseFee;
            uint collectedCashbacks = suppliedQuantity - utilisableQuantity * (1e18 + _operationBaseFee) / DENOMINATOR;
            uint collectedBaseDepegFee = collectedCashbacks * context.depegBaseFee / DENOMINATOR;
            asset.collectedCashbacks = asset.collectedCashbacks + collectedCashbacks - collectedBaseDepegFee;
            asset.collectedFees = asset.collectedFees + collectedBaseDepegFee;
        }

        asset.quantity = asset.quantity + utilisableQuantity;
        context.usdCap = context.usdCap + utilisableQuantity * asset.price / DENOMINATOR;
        asset.collectedFees = asset.collectedFees + utilisableQuantity * context.operationBaseFee / DENOMINATOR;
    }

    function burnTrace(MpContext memory context, MpAsset memory asset, uint mintPrice, uint utilisableQuantity)
        internal
        pure
        returns (uint suppliedQuantity, uint cashback, uint fees)
    {
        require(utilisableQuantity <= asset.quantity, "MULTIPOOL: QE");

        uint withFees;
        uint noFees = utilisableQuantity * (1e18 + context.operationBaseFee) / DENOMINATOR;

        uint deviationWithFees;
        {
            {
                withFees = unsign(
                    getSuppliableBurnQuantityReversed(
                        sign(utilisableQuantity), sign(context), sign(asset), sign(mintPrice)
                    )
                );
                deviationWithFees =
                    calculateDeviationBurnTrace(context, asset, withFees, withFees * asset.price / mintPrice, mintPrice);
            }
        }
        uint deviationNoFees =
            calculateDeviationBurnTrace(context, asset, noFees, noFees * asset.price / mintPrice, mintPrice);
        uint deviationOldNoFees =
            calculateDeviationBurnTrace(context, asset, 0, noFees * asset.price / mintPrice, mintPrice);

        if (deviationNoFees <= deviationOldNoFees) {
            suppliedQuantity = noFees;
            require(suppliedQuantity <= asset.quantity, "MULTIPOOL: QE");

            if (deviationOldNoFees != 0) {
                cashback = (asset.collectedCashbacks * (deviationOldNoFees - deviationNoFees)) / deviationOldNoFees;
            }
        } else {
            suppliedQuantity = withFees;
            require(suppliedQuantity <= asset.quantity, "MULTIPOOL: QE");
            require(deviationWithFees < context.deviationLimit, "MULTIPOOL: DO");
            require(withFees != 0, "MULTIPOOL: CF");

            uint _operationBaseFee = context.operationBaseFee;
            uint _depegBaseFee = context.depegBaseFee;
            uint collectedCashbacks = suppliedQuantity - utilisableQuantity * (1e18 + _operationBaseFee) / DENOMINATOR;
            uint collectedBaseDepegFee = (collectedCashbacks * _depegBaseFee) / DENOMINATOR;
            cashback = collectedCashbacks - collectedBaseDepegFee;
            fees += collectedBaseDepegFee;
        }

        fees += utilisableQuantity * context.operationBaseFee / DENOMINATOR;
    }

    function getUtilisableMintQuantity(
        SD59x18 suppliedQuantity,
        MpContextSigned memory context,
        MpAssetSigned memory asset
    ) internal pure returns (SD59x18 utilisableQuantity) {
        SD59x18 B = (sd(1e18) + context.operationBaseFee);
        SD59x18 m = sd(1e18) - asset.share / context.totalTargetShares;
        SD59x18 C = context.halfDeviationFee / context.deviationLimit;

        {
            {
                SD59x18 a = (B * (context.deviationLimit - m) + C * m) * asset.price;
                SD59x18 b = (context.deviationLimit - m) * (context.usdCap * B - suppliedQuantity * asset.price)
                    - (B - C) * (asset.quantity * asset.price - context.usdCap) + C * m * context.usdCap;
                SD59x18 c = (asset.quantity * asset.price - context.usdCap) * suppliedQuantity
                    - (context.deviationLimit - m) * context.usdCap * suppliedQuantity;

                SD59x18 d = b.powu(2) - sd(4e18) * a * c;

                SD59x18 cmp;
                {
                    {
                        cmp = -(asset.quantity * asset.price + context.usdCap * (m - sd(1e18))) / (m * asset.price);
                    }
                }

                if (d >= sd(0)) {
                    d = d.sqrt();
                    SD59x18 x1 = (-b - d) / sd(2e18) / a;
                    SD59x18 x2 = (-b + d) / sd(2e18) / a;

                    SD59x18 _suppliedQuantity = suppliedQuantity;

                    {
                        if (x1 > cmp && x1 > sd(0) && x1 < _suppliedQuantity) {
                            utilisableQuantity = utilisableQuantity + x1;
                        }
                        if (x2 > cmp && x2 > sd(0) && x2 < _suppliedQuantity) {
                            utilisableQuantity = utilisableQuantity + x2;
                        }
                    }
                }
            }
        }

        {
            {
                SD59x18 a = (B * (context.deviationLimit + m) - C * m) * asset.price;
                SD59x18 b = (context.deviationLimit + m) * (context.usdCap * B - suppliedQuantity * asset.price)
                    + (B - C) * (asset.quantity * asset.price - context.usdCap) - C * m * context.usdCap;
                SD59x18 c = -(asset.quantity * asset.price - context.usdCap) * suppliedQuantity
                    - (context.deviationLimit + m) * context.usdCap * suppliedQuantity;

                SD59x18 d = b.powu(2) - sd(4e18) * a * c;

                SD59x18 cmp;
                {
                    {
                        cmp = -(asset.quantity * asset.price + context.usdCap * (m - sd(1e18))) / (m * asset.price);
                    }
                }

                if (d >= sd(0)) {
                    d = d.sqrt();
                    SD59x18 x3 = (-b - d) / sd(2e18) / a;
                    SD59x18 x4 = (-b + d) / sd(2e18) / a;

                    SD59x18 _suppliedQuantity = suppliedQuantity;
                    {
                        if (x3 < cmp && x3 > sd(0) && x3 < _suppliedQuantity) {
                            utilisableQuantity = utilisableQuantity + x3;
                        }
                        if (x4 < cmp && x4 > sd(0) && x4 < _suppliedQuantity) {
                            utilisableQuantity = utilisableQuantity + x4;
                        }
                    }
                }
            }
        }
    }

    function getSuppliableBurnQuantity(
        SD59x18 utilisableQuantity,
        MpContextSigned memory context,
        MpAssetSigned memory asset
    ) internal pure returns (SD59x18 suppliedQuantity) {
        SD59x18 B = (sd(1e18) + context.operationBaseFee);
        SD59x18 m = sd(1e18) - asset.share / context.totalTargetShares;
        SD59x18 C = context.halfDeviationFee / context.deviationLimit;

        {
            {
                SD59x18 a = -(context.deviationLimit - m) * asset.price;
                SD59x18 b = ((B * asset.price * utilisableQuantity) + context.usdCap) * (context.deviationLimit - m)
                    + C * m * asset.price * utilisableQuantity - (asset.quantity * asset.price - context.usdCap);
                SD59x18 c = -B * context.usdCap * utilisableQuantity * (context.deviationLimit - m)
                    + (asset.quantity * asset.price - context.usdCap) * utilisableQuantity * (B - C)
                    - C * m * context.usdCap * utilisableQuantity;

                SD59x18 d = b.powu(2) - sd(4e18) * a * c;

                SD59x18 q = (asset.quantity * asset.price - context.usdCap);
                SD59x18 t = context.usdCap;
                SD59x18 p = asset.price;
                SD59x18 dl = context.deviationLimit;
                SD59x18 cmp = (q + m * t) / (m * p);

                if (d >= sd(0)) {
                    d = d.sqrt();
                    SD59x18 x1 = (-b - d) / sd(2e18) / a;
                    SD59x18 x2 = (-b + d) / sd(2e18) / a;

                    {
                        {
                            if (t - x1 * p != sd(0)) {
                                if ((m + q / (t - x1 * p)).abs() < dl && x1 < cmp) {
                                    suppliedQuantity =
                                        suppliedQuantity > x1 || suppliedQuantity == sd(0) ? x1 : suppliedQuantity;
                                }
                            }
                        }
                    }
                    {
                        {
                            if (t - x2 * p != sd(0)) {
                                if ((m + q / (t - x2 * p)).abs() < dl && x2 < cmp) {
                                    suppliedQuantity =
                                        suppliedQuantity > x2 || suppliedQuantity == sd(0) ? x2 : suppliedQuantity;
                                }
                            }
                        }
                    }
                }
            }
        }

        {
            {
                SD59x18 a = (context.deviationLimit + m) * asset.price;
                SD59x18 b = -((B * asset.price * utilisableQuantity) + context.usdCap) * (context.deviationLimit + m)
                    + C * m * asset.price * utilisableQuantity - (asset.quantity * asset.price - context.usdCap);
                SD59x18 c = B * context.usdCap * utilisableQuantity * (context.deviationLimit + m)
                    + (asset.quantity * asset.price - context.usdCap) * utilisableQuantity * (B - C)
                    - C * m * context.usdCap * utilisableQuantity;

                SD59x18 d = b.powu(2) - sd(4e18) * a * c;

                SD59x18 q = (asset.quantity * asset.price - context.usdCap);
                SD59x18 t = context.usdCap;
                SD59x18 p = asset.price;
                SD59x18 dl = context.deviationLimit;
                SD59x18 cmp = (q + m * t) / (m * p);

                if (d >= sd(0)) {
                    d = d.sqrt();
                    SD59x18 x3 = (-b - d) / sd(2e18) / a;
                    SD59x18 x4 = (-b + d) / sd(2e18) / a;

                    {
                        {
                            if (t - x3 * p != sd(0)) {
                                if ((m + q / (t - x3 * p)).abs() < dl && x3 > cmp) {
                                    suppliedQuantity =
                                        suppliedQuantity > x3 || suppliedQuantity == sd(0) ? x3 : suppliedQuantity;
                                }
                            }
                        }
                    }
                    {
                        {
                            if (t - x4 * p != sd(0)) {
                                if ((m + q / (t - x4 * p)).abs() < dl && x4 > cmp) {
                                    suppliedQuantity =
                                        suppliedQuantity > x4 || suppliedQuantity == sd(0) ? x4 : suppliedQuantity;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    function getSuppliableBurnQuantityReversed(
        SD59x18 utilisableQuantity,
        MpContextSigned memory context,
        MpAssetSigned memory asset,
        SD59x18 mintPrice
    ) internal pure returns (SD59x18 suppliedQuantity) {
        SD59x18[] memory repl = new SD59x18[](7);
        {
            {
                SD59x18 m = mintPrice;
                SD59x18 s = asset.share / context.totalTargetShares;
                SD59x18 dt = context.deviationLimit - s;
                SD59x18 f = (sd(1e18) + context.operationBaseFee);
                SD59x18 dfh = context.deviationLimit * f - context.halfDeviationFee;
                SD59x18 bt = asset.price * utilisableQuantity * (s - sd(1e18)) + asset.price * asset.quantity;
                repl[0] = m;
                repl[1] = s;
                repl[2] = dt;
                repl[3] = f;
                repl[4] = dfh;
                repl[5] = bt;
                repl[6] = utilisableQuantity;
            }
        }

        SD59x18 b = asset.price * context.deviationLimit * repl[6]
            * (-context.deviationLimit * (repl[3] + repl[0]) + repl[3] * repl[1])
            + context.deviationLimit * repl[0] * repl[5] - asset.price * context.halfDeviationFee * repl[1] * repl[6]
            + context.usdCap * context.deviationLimit * repl[0] * repl[2];
        SD59x18 c = repl[0] * repl[6]
            * (
                asset.price * context.deviationLimit * context.deviationLimit * repl[3] * repl[6] - repl[5] * repl[4]
                    - context.usdCap * (context.deviationLimit * repl[3] * repl[2] + context.halfDeviationFee * repl[1])
            );
        SD59x18 a = asset.price * context.deviationLimit * repl[2];

        {
            {
                SD59x18 d = b.powu(2) - sd(4e18) * a * c;
                if (d >= sd(0)) {
                    d = d.sqrt();
                    SD59x18 x1 = (-b - d) / sd(2e18) / a;
                    SD59x18 x2 = (-b + d) / sd(2e18) / a;

                    x1 = x1 > sd(0) ? x1 : sd(0);
                    x2 = x2 > sd(0) ? x2 : sd(0);
                    suppliedQuantity = x1 < x2 ? x1 : x2;
                }
            }
        }
    }
}

