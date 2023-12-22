// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import "./SafeERC20.sol";
import {DataTypes} from "./DataTypes.sol";
import {Math} from "./Math.sol";
import {Errors} from "./Errors.sol";
import {ILPTokenSVS} from "./ILPTokenSVS.sol";
import {LPTokenSVS} from "./LPTokenSVS.sol";
import {MathHelpers} from "./MathHelpers.sol";
import {IAddressesRegistry} from "./IAddressesRegistry.sol";
import {IConnectorRouter} from "./IConnectorRouter.sol";
import {IERC20} from "./IERC20.sol";
import {ISVSCollectionConnector} from "./ISVSCollectionConnector.sol";
import {IPriceOracleConnector} from "./IPriceOracleConnector.sol";
import {IVault1155} from "./IVault1155.sol";
import {ISVS} from "./ISVS.sol";

/**
 * @title library for pool logic functions for the SVS Pools with single collection
 * @author Souq.Finance
 * @notice License: https://souq-exchange.s3.amazonaws.com/LICENSE.md
 */

library PoolSVSLogic {
    using SafeERC20 for IERC20;
    using Math for uint256;
    /**
     * @dev Emitted when tokens different than the tokens used by the pool are rescued for receivers by the admin
     * @param admin The admin that executed the function
     * @param token The address of the token contract
     * @param amount The amount of tokens
     * @param receiver The address of the receiver
     */
    event Rescued(address admin, address token, uint256 amount, address receiver);

    /**
     * @dev Emitted when a new LP Token is deployed
     * @param LPAdress The address of the LP Token
     * @param poolAddress The address of the liquidity pool that deployed it
     * @param tokens the addresses of the ERC1155 tokens that the liquidity pool utilizes
     * @param symbol the symbol of the LP Token
     * @param name the name of the LP Token
     * @param decimals the decimals of the LP Token
     */
    event LPTokenDeployed(address LPAdress, address poolAddress, address[] tokens, string symbol, string name, uint8 decimals);
    /**
     * @dev Emitted when a new sub pool is added by the admin
     * @param admin The admin that executed the function
     * @param f the initial F of the new pool
     * @param start the initial start time of the new pool
     * @param lockupTime the lockup time of the new pool (ex. 1 month or 3 months or 6)
     * @param id the id of the new sub pool
     */
    event AddedSubPool(address admin, uint256 f, uint256 start, uint256 lockupTime, uint256 id);

    /**
     * @dev Emmitted when the status of specific subpools is modified
     * @param admin The admin that executed the function
     * @param subPoolIds The sub pool ids array
     * @param newStatus The new status, enabled=true or disabled=false
     */
    event ChangedSubpoolStatus(address admin, uint256[] subPoolIds, bool newStatus);

    /**
     * @dev Function to get the TVL of a specific sub pool
     * @param subPools The subpools array
     * @param subPoolId The id of the sub pool
     * @return subpool DataTypes.AMMSubPoolSVSDetails object
     */
    function getPool(
        DataTypes.AMMSubPoolSVS[] storage subPools,
        uint256 subPoolId
    ) external view returns (DataTypes.AMMSubPoolSVSDetails memory subpool) {
        subpool.reserve = subPools[subPoolId].reserve;
        subpool.totalShares = subPools[subPoolId].totalShares;
        subpool.start = subPools[subPoolId].start;
        subpool.lockupTime = subPools[subPoolId].lockupTime;
        subpool.F = subPools[subPoolId].F;
        subpool.status = subPools[subPoolId].status;
    }

    /**
     * @dev Function to calculate the total value of a sub pool
     * @param subPools the sub pools array
     * @param v The calculated v in the bonding curve
     * @param subPoolId the sub pool id
     * @return uint256 The total value of a subpool
     */
    function calculateTotal(DataTypes.AMMSubPoolSVS[] storage subPools, uint256 v, uint256 subPoolId) public view returns (uint256) {
        return subPools[subPoolId].reserve + MathHelpers.convertFromWad(subPools[subPoolId].totalShares * v * subPools[subPoolId].F);
    }

    // /**
    //  * @dev Function to get the total TVL of the liquidity pool from its subpools
    //  * @param subPools The subpools array
    //  * @param poolData the pool data
    //  * @param addressesRegistry the addresses registry contract
    //  * @return total The TVL
    //  */
    // function getTVL(
    //     DataTypes.AMMSubPoolSVS[] storage subPools,
    //     DataTypes.PoolSVSData storage poolData,
    //     address addressesRegistry
    // ) public view returns (uint256 total) {
    //     uint256 v = getV(addressesRegistry, poolData, subPools);
    //     for (uint256 i; i < subPools.length; ++i) {
    //         total += calculateTotal(subPools, v, i);
    //     }
    // }

    // /**
    //  * @dev Function to get the total active TVL of the liquidity pool from its active subpools
    //  * @param subPools The subpools array
    //  * @param poolData the pool data
    //  * @param addressesRegistry the addresses registry contract
    //  * @return total The TVL
    //  */
    // function getTVLActive(
    //     DataTypes.AMMSubPoolSVS[] storage subPools,
    //     DataTypes.PoolSVSData storage poolData,
    //     address addressesRegistry
    // ) public view returns (uint256 total) {
    //     uint256 v = getV(addressesRegistry, poolData, subPools);
    //     for (uint256 i; i < subPools.length; ++i) {
    //         if (subPools[i].status) {
    //             total += calculateTotal(subPools, v, i);
    //         }
    //     }
    // }

    // /**
    //  * @dev Function to get the LP Token price by dividing the TVL over the total minted tokens
    //  * @param addressesRegistry the addresses registry contract
    //  * @param poolData the pool data
    //  * @param subPools The subpools array
    //  * @return uint256 The LP Price
    //  */
    // function getLPPrice(
    //     DataTypes.AMMSubPoolSVS[] storage subPools,
    //     address addressesRegistry,
    //     DataTypes.PoolSVSData storage poolData
    // ) public view returns (uint256) {
    //     uint256 total = ILPTokenSVS(poolData.poolLPToken).getTotal();
    //     uint256 tvl = getTVL(subPools, poolData, addressesRegistry);
    //     if (total == 0 || tvl == 0) {
    //         return MathHelpers.convertToWad(1);
    //     }
    //     return MathHelpers.convertToWad(tvl) / total;
    // }

    // /**
    //  * @dev Function to get the TVL and LP Token price together which saves gas if we need both variables
    //  * @param addressesRegistry the addresses registry contract
    //  * @param poolData the pool data
    //  * @param subPools The subpools array
    //  * @return (uint256,uint256) The TVL and LP Price
    //  */
    // function getTVLAndLPPrice(
    //     DataTypes.AMMSubPoolSVS[] storage subPools,
    //     address addressesRegistry,
    //     DataTypes.PoolSVSData storage poolData
    // ) external view returns (uint256, uint256) {
    //     uint256 total = ILPTokenSVS(poolData.poolLPToken).getTotal();
    //     uint256 tvl = getTVL(subPools, poolData, addressesRegistry);
    //     if (total == 0 || tvl == 0) {
    //         return (tvl, MathHelpers.convertToWad(1));
    //     }
    //     return (tvl, (MathHelpers.convertToWad(tvl) / total));
    // }

    // /**
    //  * @dev Function that returns the sum of the VIT values including their amounts per 1 share
    //  * @notice this causes a circular dependency if the lp token is one of the VITs
    //  * @param addressesRegistry the addresses registry used to link the connectors
    //  * @param poolData The pool data
    //  * @return v the total sum denoted as V
    //  */
    // function getV(
    //     address addressesRegistry,
    //     DataTypes.PoolSVSData storage poolData,
    //     DataTypes.AMMSubPoolSVS[] storage subPools
    // ) public view returns (uint256 v) {
    //     (address[] memory VITs, uint256[] memory amounts) = getCollectionConnector(addressesRegistry, poolData).getVITs(poolData.tokens[0]);
    //     uint256 stablePrice = uint(getPriceConnector(addressesRegistry, poolData.stable).getTokenPrice(poolData.stable));
    //     for (uint i; i < VITs.length; ++i) {
    //         //TODO: test negative?
    //         //The amounts are in wei in the vault1155
    //         if (VITs[i] == poolData.poolLPToken) {
    //             v += MathHelpers.convertFromBiggerToSmaller(
    //                 amounts[i] * getLPPrice(subPools, addressesRegistry, poolData) * stablePrice,
    //                 42,
    //                 6
    //             );
    //         } else {
    //             v += MathHelpers.convertFromBiggerToSmaller(
    //                 amounts[i] * uint(getPriceConnector(addressesRegistry, VITs[i]).getTokenPrice(VITs[i])) * stablePrice,
    //                 30,
    //                 6
    //             );
    //         }
    //     }
    // }

    function calculateV(
        uint256 lpPrice,
        address[] memory VITs,
        uint256[] memory amounts,
        uint256 stablePrice,
        address addressesRegistry,
        DataTypes.PoolSVSData storage poolData
    ) public view returns (uint256 v) {
        for (uint i; i < VITs.length; ++i) {
            //The amounts are in wei in the vault1155
            //lpPrice is in wei
            //stablePrice are 6 decimals
            //Token prices are 6 decimals
            if (VITs[i] == poolData.poolLPToken) {
                v += MathHelpers.convertFromBiggerToSmaller(amounts[i] * lpPrice * stablePrice, 42, 6);
            } else {
                v += MathHelpers.convertFromBiggerToSmaller(
                    amounts[i] * uint(getPriceConnector(addressesRegistry, VITs[i]).getTokenPrice(VITs[i])) * stablePrice,
                    30,
                    6
                );
            }
        }
    }

    function calculateTVL(uint256 v, DataTypes.AMMSubPoolSVS[] storage subPools) public view returns (uint256 tvl, uint256 tvlActive) {
        uint256 total;
        for (uint256 i; i < subPools.length; ++i) {
            total = calculateTotal(subPools, v, i);
            tvl += total;
            if (subPools[i].status) {
                tvlActive += total;
            }
        }
    }

    function calculateLiquidityDetailsIterative(
        address addressesRegistry,
        DataTypes.PoolSVSData storage poolData,
        DataTypes.AMMSubPoolSVS[] storage subPools
    ) public view returns (uint256 v, uint256 tvl, uint256 tvlActive, uint256 lpPrice) {
        DataTypes.LiquidityDetailsVars memory vars;
        (vars.VITs, vars.amounts) = getCollectionConnector(addressesRegistry, poolData).getVITs(poolData.tokens[0]);
        vars.stablePrice = uint(getPriceConnector(addressesRegistry, poolData.stable).getTokenPrice(poolData.stable));
        vars.total = ILPTokenSVS(poolData.poolLPToken).getTotal();
        lpPrice = poolData.liquidityLimit.lastLpPrice;
        for (vars.i; vars.i < 1; ++vars.i) {
            v = calculateV(lpPrice, vars.VITs, vars.amounts, vars.stablePrice, addressesRegistry, poolData);
            (tvl, tvlActive) = calculateTVL(v, subPools);
            lpPrice = (vars.total == 0 || tvl == 0) ? MathHelpers.convertToWad(1) : MathHelpers.convertToWad(tvl) / vars.total;
        }
    }

    /**
     * @dev Function to get the actual fee value structure depending on swap direction
     * @param operation The direction of the swap
     * @param value value of the amount to compute the fees for
     * @param fee The fee configuration of the liquidity pool
     * @return feeReturn The return fee structure that has the ratios
     */
    function calculateFees(
        DataTypes.OperationType operation,
        uint256 value,
        DataTypes.PoolFee storage fee
    ) public view returns (DataTypes.FeeReturn memory feeReturn) {
        uint256 actualValue;
        if (operation == DataTypes.OperationType.buyShares) {
            actualValue = MathHelpers.convertFromWadPercentage(value * (MathHelpers.convertToWadPercentage(1) - fee.lpBuyFee));
            feeReturn.royalties = MathHelpers.convertFromWadPercentage(fee.royaltiesBuyFee * actualValue);
            feeReturn.lpFee = MathHelpers.convertFromWadPercentage(fee.lpBuyFee * value);
            feeReturn.protocolFee = MathHelpers.convertFromWadPercentage(fee.protocolBuyRatio * actualValue);
        } else if (operation == DataTypes.OperationType.sellShares) {
            actualValue = MathHelpers.convertToWadPercentage(value) / (MathHelpers.convertToWadPercentage(1) - fee.lpSellFee);
            feeReturn.royalties = MathHelpers.convertFromWadPercentage(fee.royaltiesSellFee * actualValue);
            feeReturn.lpFee = MathHelpers.convertFromWadPercentage(fee.lpSellFee * value);
            feeReturn.protocolFee = MathHelpers.convertFromWadPercentage(fee.protocolSellRatio * actualValue);
        }
        feeReturn.swapFee = feeReturn.lpFee + feeReturn.protocolFee;
        feeReturn.totalFee = feeReturn.royalties + feeReturn.swapFee;
    }

    /**
     * @dev Function to add two feeReturn structures and output 1
     * @param x the first feeReturn struct
     * @param y the second feeReturn struct
     * @return z The return data structure
     */
    function addFees(DataTypes.FeeReturn memory x, DataTypes.FeeReturn memory y) external pure returns (DataTypes.FeeReturn memory z) {
        //Add all the fees together
        z.totalFee = x.totalFee + y.totalFee;
        z.royalties = x.royalties + y.royalties;
        z.protocolFee = x.protocolFee + y.protocolFee;
        z.lpFee = x.lpFee + y.lpFee;
        z.swapFee = x.swapFee + y.swapFee;
    }

    /**
     * @dev Function to multiply a fee structure by a number and divide by a den
     * @param fee the original feeReturn struct
     * @param num the numerator
     * @param den The denominator
     * @return feeReturn The new fee structure
     */
    function multiplyFees(
        DataTypes.FeeReturn memory fee,
        uint256 num,
        uint256 den
    ) external pure returns (DataTypes.FeeReturn memory feeReturn) {
        feeReturn.totalFee = (fee.totalFee * num) / den;
        feeReturn.royalties = (fee.royalties * num) / den;
        feeReturn.protocolFee = (fee.protocolFee * num) / den;
        feeReturn.lpFee = (fee.lpFee * num) / den;
        feeReturn.swapFee = (fee.swapFee * num) / den;
    }

    /**
     * @dev Function to calculate the price of a share in a sub pool\
     * @param operation the operation direction
     * @param subPoolId the sub pool id
     * @param addressesRegistry the addresses registry contract
     * @param poolData the pool data
     * @param subPools The sub pools array
     * @return sharesReturn The return data structure
     */
    function CalculateShares(
        DataTypes.OperationType operation,
        uint256 subPoolId,
        uint256 shares,
        bool useFee,
        address addressesRegistry,
        DataTypes.PoolSVSData storage poolData,
        DataTypes.AMMSubPoolSVS[] storage subPools
    ) external view returns (DataTypes.SharesCalculationReturn memory sharesReturn) {
        require(
            subPools[subPoolId].totalShares >= shares || operation != DataTypes.OperationType.buyShares,
            Errors.NOT_ENOUGH_SUBPOOL_SHARES
        );
        //Iterative approach
        DataTypes.SharesCalculationVars memory vars;
        //Initial values
        (vars.V, , , sharesReturn.lastLpPrice) = calculateLiquidityDetailsIterative(addressesRegistry, poolData, subPools);
        vars.PV_0 = MathHelpers.convertFromWad(vars.V * subPools[subPoolId].F);
        sharesReturn.PV = vars.PV_0;
        //Calculate steps
        vars.steps = shares / poolData.iterativeLimit.maxBulkStepSize;
        //At first the stable = reserve
        vars.stable = subPools[subPoolId].reserve;
        vars.shares = subPools[subPoolId].totalShares;
        //Iterating step sizes for enhanced results. If amount = 50, and stepsize is 15, then we iterate 4 times 15,15,15,5
        for (vars.stepIndex; vars.stepIndex < vars.steps + 1; ++vars.stepIndex) {
            vars.stepAmount = vars.stepIndex == vars.steps
                ? (shares - ((vars.stepIndex) * poolData.iterativeLimit.maxBulkStepSize))
                : poolData.iterativeLimit.maxBulkStepSize;
            if (vars.stepAmount == 0) break;
            //The value of the shares are priced first at last PV
            vars.value = vars.stepAmount * vars.PV_0;
            if (useFee) vars.fees = calculateFees(operation, vars.value, poolData.fee);
            //Iterate the calculations while keeping PV_0 and stable the same and using the new PV to calculate the average and reiterate
            for (vars.i = 0; vars.i < poolData.iterativeLimit.iterations; ++vars.i) {
                if (operation == DataTypes.OperationType.buyShares) {
                    //if buying shares, the pool receives stable plus the swap fee and gives out shares
                    vars.newCash = vars.stable + vars.value + (useFee ? vars.fees.lpFee : 0);
                    vars.den =
                        vars.newCash +
                        ((poolData.coefficients.coefficientB * (vars.shares - vars.stepAmount) * sharesReturn.PV) /
                            poolData.coefficients.coefficientC);
                } else if (operation == DataTypes.OperationType.sellShares) {
                    require(vars.stable >= vars.value, Errors.NOT_ENOUGH_SUBPOOL_RESERVE);
                    //if selling shares, the pool receives shares and gives out stable - total fees from the reserve
                    vars.newCash = vars.stable - vars.value + (useFee ? vars.fees.lpFee : 0);
                    vars.den =
                        vars.newCash +
                        ((poolData.coefficients.coefficientB * (vars.shares + vars.stepAmount) * sharesReturn.PV) /
                            poolData.coefficients.coefficientC);
                }
                //Calculate new PV and F
                sharesReturn.F = vars.den == 0 ? 0 : (poolData.coefficients.coefficientA * vars.newCash) / vars.den;
                sharesReturn.PV = MathHelpers.convertFromWad(vars.V * sharesReturn.F);
                //Swap PV is the price used for the swapping in the newCash
                vars.swapPV = vars.stepAmount > 1 ? ((sharesReturn.PV + vars.PV_0) / 2) : vars.PV_0;
                vars.value = vars.stepAmount * vars.swapPV;
                if (useFee) vars.fees = calculateFees(operation, vars.value, poolData.fee);
            }
            //We add/subtract the shares to be used in the next stepsize iteration
            vars.shares = operation == DataTypes.OperationType.buyShares ? vars.shares - vars.stepAmount : vars.shares + vars.stepAmount;
            //At the end of iterations, the stable is now the last cash value
            vars.stable = vars.newCash;
            //The starting PV is now the last PV value
            vars.PV_0 = sharesReturn.PV;
            //Add the amounts to the return
            sharesReturn.amount += vars.stepAmount;
        }
        //Calculate the actual value to return
        sharesReturn.value = operation == DataTypes.OperationType.buyShares
            ? vars.stable - subPools[subPoolId].reserve
            : subPools[subPoolId].reserve - vars.stable;
        //Calculate the final fees
        if (useFee) sharesReturn.fees = calculateFees(operation, sharesReturn.value, poolData.fee);
        //Average the swap PV in the return
        sharesReturn.swapPV = sharesReturn.value / sharesReturn.amount;
    }

    /**
     * @dev Function to update the price iteratively in a subpool
     * @notice This updates the last lp price
     * @param subPools The sub pools array
     * @param addressesRegistry the addresses registry contract
     * @param poolData The pool data struct
     * @param subPoolId the sub pool id
     */
    function updatePriceIterative(
        address addressesRegistry,
        DataTypes.PoolSVSData storage poolData,
        DataTypes.AMMSubPoolSVS[] storage subPools,
        uint256 subPoolId
    ) public {
        //coef is converted to wad and we also need F to be converted to wad
        uint256 num = ((poolData.coefficients.coefficientA * subPools[subPoolId].reserve));
        (uint256 v, , , uint256 lastLpPrice) = calculateLiquidityDetailsIterative(addressesRegistry, poolData, subPools);
        uint256 temp = poolData.coefficients.coefficientB * subPools[subPoolId].totalShares * v;
        uint256 den = (subPools[subPoolId].reserve +
            (MathHelpers.convertFromWad(temp * subPools[subPoolId].F) / poolData.coefficients.coefficientC));
        subPools[subPoolId].F = den == 0 ? 0 : num / den;
        //Iteration 0 is done, iterate through the rest
        if (poolData.iterativeLimit.iterations > 1) {
            for (uint256 i; i < poolData.iterativeLimit.iterations - 1; ++i) {
                den = (subPools[subPoolId].reserve +
                    (MathHelpers.convertFromWad(subPools[subPoolId].F * temp) / poolData.coefficients.coefficientC));
                subPools[subPoolId].F = den == 0 ? 0 : num / den;
            }
        }
        poolData.liquidityLimit.lastLpPrice = lastLpPrice;
    }

    /**
     * @dev Function to add a new sub pool
     * @param f The initial F value of the sub pool
     * @param start The start time of the subpool
     * @param lockupTime The lockup time of the subpool (ex. 1 month)
     * @param subPools The subpools array
     */
    function addSubPool(uint256 f, uint256 start, uint256 lockupTime, DataTypes.AMMSubPoolSVS[] storage subPools) public {
        DataTypes.AMMSubPoolSVS storage newPool = subPools.push();
        newPool.reserve = 0;
        newPool.totalShares = 0;
        newPool.F = f;
        newPool.lockupTime = lockupTime;
        newPool.start = start;
        newPool.status = false;
        emit AddedSubPool(msg.sender, f, start, lockupTime, subPools.length - 1);
    }

    /**
     * @dev Function to add a new sub pool(s) phase automatically according to the collection lockuptimes and maturity range
     * @param f The initial F value of the sub pool
     * @param start the start of subpool maturity
     * @param addressesRegistry The addresses Registry contract address
     * @param poolData The pool data
     * @param subPools The subpools array
     */
    function addSubPoolsAuto(
        uint256 f,
        uint256 start,
        address addressesRegistry,
        DataTypes.PoolSVSData storage poolData,
        DataTypes.AMMSubPoolSVS[] storage subPools
    ) public {
        uint256 lastStart = subPools.length > 1
            ? (subPools[subPools.length - 1].start + poolData.maxMaturityRange)
            : block.timestamp - (block.timestamp % 1 days);
        uint256[] memory lockupTimes = getCollectionConnector(addressesRegistry, poolData).getLockupTimes(poolData.tokens[0]);
        while (lastStart <= start) {
            for (uint256 i; i < lockupTimes.length; ++i) {
                DataTypes.AMMSubPoolSVS storage newPool = subPools.push();
                newPool.reserve = 0;
                newPool.totalShares = 0;
                newPool.F = f;
                newPool.lockupTime = lockupTimes[i];
                newPool.start = lastStart;
                newPool.status = false;
                emit AddedSubPool(msg.sender, f, lastStart, lockupTimes[i], subPools.length - 1);
            }
            lastStart += poolData.maxMaturityRange;
        }
    }

    /**
     * @dev Function to find and save a new token id in the tokenids of a subpool
     * @param tokenId the token id
     * @param subPoolId The subpool id
     * @param subPools The subpools array
     */
    function findAndSaveTokenId(
        uint256 tokenId,
        uint256 subPoolId,
        uint256 start,
        uint256 lockupTime,
        DataTypes.AMMSubPoolSVS[] storage subPools
    ) external returns (uint256 foundTokenId) {
        bool tokenIdFound;
        for (uint256 j = 0; j < subPools[subPoolId].tokenIds.length; ++j) {
            if (subPools[subPoolId].tokenIds[j] == tokenId) {
                tokenIdFound = true;
                foundTokenId = tokenId;
                break;
            }
        }
        if (!tokenIdFound) {
            subPools[subPoolId].tokenIds.push(tokenId);
            foundTokenId = subPools[subPoolId].tokenIds.length - 1;
        }
        if (subPools[subPoolId].shares[tokenId].start == 0 && (start + lockupTime) > block.timestamp) {
            subPools[subPoolId].shares[tokenId].start = start;
            subPools[subPoolId].shares[tokenId].lockupTime = lockupTime;
        }
    }

    /**
     * @dev Function to move enable or disable subpools by ids
     * @param subPoolIds The sub pool ids array
     * @param newStatus The new status, enabled=true or disabled=false
     * @param subPools The subpools array
     */
    function changeSubPoolStatus(uint256[] memory subPoolIds, bool newStatus, DataTypes.AMMSubPoolSVS[] storage subPools) external {
        for (uint256 i; i < subPoolIds.length; ++i) {
            subPools[subPoolIds[i]].status = newStatus;
        }
        emit ChangedSubpoolStatus(msg.sender, subPoolIds, newStatus);
    }

    /**
     * @dev Function that deploys the LP Token of the pool
     * @param poolAddress The address of the pool
     * @param registry The registry address
     * @param tokens The collection tokens to be used by the pool
     * @param symbol The symbol of the LP Token
     * @param name The name of the LP Token
     * @param decimals The decimals of the LP Token
     * @return address of the LP Token
     */
    function deployLPToken(
        address poolAddress,
        address registry,
        address[] memory tokens,
        string memory symbol,
        string memory name,
        uint8 decimals
    ) external returns (address) {
        ILPTokenSVS poolLPToken = new LPTokenSVS(poolAddress, registry, tokens, symbol, name, decimals);
        emit LPTokenDeployed(address(poolLPToken), poolAddress, tokens, symbol, name, decimals);
        return address(poolLPToken);
    }

    /**
     * @dev Function to rescue and send ERC20 tokens (different than the tokens used by the pool) to a receiver called by the admin
     * @param token The address of the token contract
     * @param amount The amount of tokens
     * @param receiver The address of the receiver
     * @param stableToken The address of the stablecoin to rescue
     * @param poolLPToken The address of the pool LP Token
     */
    function RescueTokens(address token, uint256 amount, address receiver, address stableToken, address poolLPToken) external {
        require(token != stableToken, Errors.CANNOT_RESCUE_POOL_TOKEN);
        emit Rescued(msg.sender, token, amount, receiver);
        ILPTokenSVS(poolLPToken).rescueTokens(token, amount, receiver);
    }

    /**
     * @dev Function that returns the subpool of a token id (tranche) or 0 if it matured and moved
     * @notice reverts if no subpool found
     * @param tokenId The token id
     * @param addressesRegistry The addresses Registry contract address
     * @param poolData The pool data
     * @param subPools The subpools array
     * @return subPoolIndex the subpool id
     * @return foundSubpool the found flag if there is a subpool for it
     * @return lockupStart the start of maturity of the token id
     */
    function checkSubPool(
        uint256 tokenId,
        address addressesRegistry,
        DataTypes.PoolSVSData storage poolData,
        DataTypes.AMMSubPoolSVS[] storage subPools
    ) public view returns (uint256 subPoolIndex, bool foundSubpool, uint256 lockupStart, uint256 lockupTime, bool matured) {
        (lockupStart, lockupTime) = getTokenDetails(addressesRegistry, poolData, tokenId);
        for (uint256 i; i < subPools.length; ++i) {
            if (
                lockupTime == subPools[i].lockupTime &&
                lockupStart >= (subPools[i].start) &&
                lockupStart < subPools[i].start + poolData.maxMaturityRange
            ) {
                foundSubpool = true;
                subPoolIndex = i;
                break;
            }
        }
        matured = lockupStart + lockupTime <= block.timestamp ? true : false;
    }

    /**
     * @dev Function that returns the start of a token id maturity period (tranche)
     * @param addressesRegistry the addresses registry used to link the connectors
     * @param poolData The pool data
     * @param tokenId The token id (tranche id)
     * @return start the start of that token id maturity
     * @return lockupTime the lockupTime of that token id
     */
    function getTokenDetails(
        address addressesRegistry,
        DataTypes.PoolSVSData storage poolData,
        uint256 tokenId
    ) public view returns (uint256 start, uint256 lockupTime) {
        ISVSCollectionConnector connector = getCollectionConnector(addressesRegistry, poolData);
        start = connector.getAttribute(poolData.tokens[0], tokenId);
        lockupTime = connector.getLockupTime(poolData.tokens[0], tokenId);
    }

    /**
     * @dev Function that returns the interface of the collection connector (vault connector)
     * @param addressesRegistry the addresses registry used to link the connectors
     * @return ISVSCollectionConnector the svs collection connector interface
     */
    function getCollectionConnector(
        address addressesRegistry,
        DataTypes.PoolSVSData storage poolData
    ) public view returns (ISVSCollectionConnector) {
        return
            ISVSCollectionConnector(
                IConnectorRouter(IAddressesRegistry(addressesRegistry).getConnectorsRouter()).getCollectionConnectorContract(
                    poolData.tokens[0]
                )
            );
    }

    /**
     * @dev Function that returns the interface of the price oracle connector
     * @param addressesRegistry the addresses registry used to link the connectors
     * @return IPriceOracleConnector the price oracle connector interface
     */
    function getPriceConnector(address addressesRegistry, address asset) public view returns (IPriceOracleConnector) {
        return
            IPriceOracleConnector(
                IConnectorRouter(IAddressesRegistry(addressesRegistry).getConnectorsRouter()).getOracleConnectorContract(asset)
            );
    }

    /**
     * @dev Function that returns the subpool ids of the given token ids
     * @param tokenIds The address of the pool
     * @param addressesRegistry the addresses registry used to link the connectors
     * @param poolData The pool data
     * @param subPools The subpools array
     * @return subs array of the subpool ids of the token ids
     */
    function getSubPools(
        uint256[] memory tokenIds,
        address addressesRegistry,
        DataTypes.PoolSVSData storage poolData,
        DataTypes.AMMSubPoolSVS[] storage subPools
    ) external view returns (uint256[] memory subs) {
        subs = new uint256[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; ++i) {
            (subs[i], , , , ) = checkSubPool(tokenIds[i], addressesRegistry, poolData, subPools);
        }
    }

    /**
     * @dev Function that gets the token of a collection if it is different (like Vault vs SVS)
     * @param poolData The pool data
     * @return address of the token
     */
    function getCollectionToken(DataTypes.PoolSVSData storage poolData) external view returns (address) {
        return IVault1155(poolData.tokens[0]).getSVS();
    }
}

