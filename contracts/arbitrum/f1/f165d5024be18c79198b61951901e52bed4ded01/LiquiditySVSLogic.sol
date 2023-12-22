// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import "./SafeERC20.sol";
import {DataTypes} from "./DataTypes.sol";
import {PoolSVSLogic} from "./PoolSVSLogic.sol";
import {MathHelpers} from "./MathHelpers.sol";
import {Math} from "./Math.sol";
import {Errors} from "./Errors.sol";
import {IERC20} from "./IERC20.sol";
import {IERC1155} from "./IERC1155.sol";
import {ILPTokenSVS} from "./ILPTokenSVS.sol";
// import "hardhat/console.sol";

/**
 * @title library for Liquidity logic of SVS pools with single collection
 * @author Souq.Finance
 * @notice Defines the logic functions for the AMM and MME that operate SVS shares
 * @notice License: https://souq-exchange.s3.amazonaws.com/LICENSE.md
 */

library LiquiditySVSLogic {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using PoolSVSLogic for DataTypes.AMMSubPoolSVS[];

    /**
     * @dev Emitted when the user initiates deposit of stablecoins and shares into a subpool
     * @param user The user address
     * @param subPoolId The subPool id
     * @param stableIn The amount of stablecoin inputted
     * @param params The token ids[] and amounts[] structure
     * @param totalShares The new total shares count
     * @param F The new F
     */
    event DepositInitiated(
        address user,
        uint256 subPoolId,
        uint256 stableIn,
        DataTypes.Shares1155Params params,
        uint256 totalShares,
        uint256 F
    );

    /**
     * @dev Emitted when adding liquidity by a liqduity provider using stablecoins
     * @param stableIn The amount of stablecoin inputted
     * @param lpAmount The amount of LP token outputted
     * @param from The address of the msg sender
     * @notice it's here to avoid the stack too deep issue for now
     */
    event AddedLiqStable(uint256 stableIn, uint256 lpAmount, address from);

    /**
     * @dev Emitted when removing liquidity by a liqduity provider
     * @param stableOut The amount of stablecoin outputted
     * @param lpAmount The amount of LP token inputted
     * @param from The address of the msg sender
     * @param queued If transaction is queued = true
     */
    event RemovedLiqStable(uint256 stableOut, uint256 lpAmount, address from, bool queued);

    /**
     * @dev Emitted when swap of stable coins occures
     * @param stableIn The amount of stablecoin supplied
     * @param fees The fees collected
     * @param user The user address
     * @param subPoolGroups The subpool groups including calculations and shares array
     */
    event SwappedStable(uint256 stableIn, DataTypes.FeeReturn fees, address user, DataTypes.SubPoolGroup[] subPoolGroups);

    /**
     * @dev Emitted when swap of shares occures
     * @param stableOut The amount of stablecoin outputted
     * @param fees The fees collected
     * @param user The user address
     * @param subPoolGroups The subpool groups including calculations and shares array
     */
    event SwappedShares(uint256 stableOut, DataTypes.FeeReturn fees, address user, DataTypes.SubPoolGroup[] subPoolGroups);

    /**
     * @dev Emitted when withdrawals are processed after the cooldown period
     * @param user The user that processed the withdrawals
     * @param transactionsCount The number of transactions processed
     */
    event WithdrawalsProcessed(address user, uint256 transactionsCount);

    /**
     * @dev Emitted when reserve is moved between subpools
     * @param admin The admin that executed the function
     * @param moverId the id of the subpool to move funds from
     * @param movedId the id of the subpool to move funds to
     * @param amount the amount of funds to move
     */
    event MovedReserve(address admin, uint256 moverId, uint256 movedId, uint256 amount);

    /**
     * @dev Emitted when the accumulated fee balances are withdrawn by the royalties and protocol wallet addresses
     * @param user The sender of the transaction
     * @param to the address to send the funds to
     * @param amount the amount being withdrawn
     * @param feeType: string - the type of fee being withdrawan (royalties/protocol)
     */
    event WithdrawnFees(address user, address to, uint256 amount, string feeType);

    /**
     * @dev Function to distribute liquidity to all subpools according to their weight
     * @notice updates the last lp price via updatePriceIterative
     * @notice the last subpool gets the remainder, if any
     * @param amount The account to deduct the stables from
     * @param tvl The TVL of the pool
     * @param addressesRegistry the addresses registry contract
     * @param poolData The liquidity pool data structure
     * @param subPools The subpools array
     */
    function distributeLiquidityToAll(
        uint256 amount,
        uint256 tvl,
        uint256 v,
        address addressesRegistry,
        DataTypes.PoolSVSData storage poolData,
        DataTypes.AMMSubPoolSVS[] storage subPools
    ) public {
        require(subPools.length > 0, Errors.NO_SUB_POOL_AVAILABLE);
        uint256 remaining = amount;
        uint256 weighted = 0;
        //Iterate through the subpools and add liquidity in a weighted manner and the remainder goes to the last subpool
        for (uint256 i = 0; i < subPools.length; ++i) {
            if (subPools[i].status) {
                if (i == subPools.length - 1) {
                    subPools[i].reserve += remaining;
                } else {
                    if (tvl == 0) {
                        subPools[i].reserve += amount / subPools.length;
                        remaining -= amount / subPools.length;
                    } else {
                        weighted = (amount * PoolSVSLogic.calculateTotal(subPools, v, i)) / tvl;
                        // console.log("weighted: ", weighted);
                        remaining -= weighted;
                        subPools[i].reserve += weighted;
                    }
                }
                PoolSVSLogic.updatePriceIterative(addressesRegistry, poolData, subPools, i);
            }
        }
    }

    /**
     * @dev Function to distribute the reserve in subpool 0 (maturity) to all active subpools
     * @notice updates the last lp price via updatePriceIterative
     * @notice the last subpool gets the remainder, if any
     * @param addressesRegistry the addresses registry contract
     * @param poolData The liquidity pool data structure
     * @param subPools The subpools array
     */
    function redistrubteLiquidity(
        address addressesRegistry,
        DataTypes.PoolSVSData storage poolData,
        DataTypes.AMMSubPoolSVS[] storage subPools
    ) external {
        if (subPools[0].reserve > 0) {
            (uint256 v, , uint256 tvlActive, ) = PoolSVSLogic.calculateLiquidityDetailsIterative(addressesRegistry, poolData, subPools);
            // console.log("tvlActive: ", tvlActive);
            if (tvlActive > 0) {
                distributeLiquidityToAll(subPools[0].reserve, tvlActive, v, addressesRegistry, poolData, subPools);
                subPools[0].reserve = 0;
            }
        }
    }

    /**
     * @dev Function to move reserves between subpools
     * @param moverId The sub pool that will move the funds from
     * @param movedId The id of the sub pool that will move the funds to
     * @param amount The amount to move
     * @param addressesRegistry The addresses Registry contract address
     * @param poolData The pool data
     * @param subPools The subpools array
     */
    function moveReserve(
        uint256 moverId,
        uint256 movedId,
        uint256 amount,
        address addressesRegistry,
        DataTypes.PoolSVSData storage poolData,
        DataTypes.AMMSubPoolSVS[] storage subPools
    ) external {
        require(subPools[moverId].reserve >= amount, Errors.NOT_ENOUGH_SUBPOOL_RESERVE);
        require(subPools.length > moverId && subPools.length > movedId, Errors.INVALID_SUBPOOL_ID);
        subPools[moverId].reserve -= amount;
        PoolSVSLogic.updatePriceIterative(addressesRegistry, poolData, subPools, moverId);
        subPools[movedId].reserve += amount;
        PoolSVSLogic.updatePriceIterative(addressesRegistry, poolData, subPools, movedId);
        emit MovedReserve(msg.sender, moverId, movedId, amount);
    }

    /**
     * @dev Function to deposit initial liquidity to a subpool
     * @notice This will work if there is an already created subpool
     * @param user The user to get the LPs
     * @param subPoolId The subpool id
     * @param stableIn The stablecoins amount to deposit
     * @param params the token ids and amounts to deposit
     * @param addressesRegistry the addresses registry contract
     * @param poolData The liquidity pool data structure
     * @param subPools The subpools array
     */
    function depositInitial(
        address user,
        uint256 subPoolId,
        uint256 stableIn,
        DataTypes.Shares1155Params memory params,
        address addressesRegistry,
        DataTypes.PoolSVSData storage poolData,
        DataTypes.AMMSubPoolSVS[] storage subPools
    ) external {
        DataTypes.SubPoolCheckerVars memory checkerVars;
        require(params.tokenIds.length == params.amounts.length, Errors.ARRAY_NOT_SAME_LENGTH);
        (checkerVars.v, checkerVars.total, , checkerVars.lpPrice) = PoolSVSLogic.calculateLiquidityDetailsIterative(
            addressesRegistry,
            poolData,
            subPools
        );
        for (uint256 i = 0; i < params.tokenIds.length; ++i) {
            (
                checkerVars.subPoolIndex,
                checkerVars.foundSubPool,
                checkerVars.lockupStart,
                checkerVars.lockupTime,
                checkerVars.matured
            ) = PoolSVSLogic.checkSubPool(params.tokenIds[i], addressesRegistry, poolData, subPools);
            require(checkerVars.subPoolIndex == subPoolId && checkerVars.foundSubPool, "NOT_SAME_SUBPOOL_DISTRIBUTION");
            subPools[subPoolId].shares[params.tokenIds[i]].amount += params.amounts[i];
            subPools[subPoolId].totalShares += params.amounts[i];
            PoolSVSLogic.findAndSaveTokenId(params.tokenIds[i], subPoolId, checkerVars.lockupStart, checkerVars.lockupTime, subPools);
            checkerVars.total += params.amounts[i];
        }
        subPools[subPoolId].reserve += stableIn;
        PoolSVSLogic.updatePriceIterative(addressesRegistry, poolData, subPools, subPoolId);
        emit DepositInitiated(user, subPoolId, stableIn, params, subPools[subPoolId].totalShares, subPools[subPoolId].F);
        if (params.tokenIds.length > 0 && checkerVars.total > 0) {
            IERC1155(PoolSVSLogic.getCollectionToken(poolData)).safeBatchTransferFrom(
                user,
                poolData.poolLPToken,
                params.tokenIds,
                params.amounts,
                ""
            );
        }
        (, checkerVars.tvl, , ) = PoolSVSLogic.calculateLiquidityDetailsIterative(addressesRegistry, poolData, subPools);
        ILPTokenSVS(poolData.poolLPToken).mint(user, MathHelpers.convertToWad(checkerVars.tvl - checkerVars.total) / checkerVars.lpPrice);
        IERC20(poolData.stable).safeTransferFrom(user, poolData.poolLPToken, stableIn);
    }

    /**
     * @dev Function to remove liquidity by stable coins
     * @param user The account to deduct the stables from
     * @param targetLP The amount of LPs required
     * @param maxStable the maximum stablecoins to transfer
     * @param addressesRegistry the addresses registry contract
     * @param poolData The liquidity pool data structure
     * @param subPools The subpools array
     */
    function addLiquidityStable(
        address user,
        uint256 targetLP,
        uint256 maxStable,
        address addressesRegistry,
        DataTypes.PoolSVSData storage poolData,
        DataTypes.AMMSubPoolSVS[] storage subPools
    ) external returns (uint256, uint256) {
        require(user != address(0), Errors.ADDRESS_IS_ZERO);
        require(IERC20(poolData.stable).allowance(user, address(this)) >= maxStable, Errors.NOT_ENOUGH_APPROVED);
        require(IERC20(poolData.stable).balanceOf(user) >= maxStable, Errors.NOT_ENOUGH_USER_BALANCE);
        DataTypes.LiqLocalVars memory vars;
        (vars.v, vars.TVL, vars.TVLActive, vars.LPPrice) = PoolSVSLogic.calculateLiquidityDetailsIterative(
            addressesRegistry,
            poolData,
            subPools
        );
        require(poolData.liquidityLimit.poolTvlLimit >= vars.TVL + maxStable, Errors.TVL_LIMIT_REACHED);
        //if TVL > 0 and deposit > TVL * limitPercentage, then revert where deposit is (requiredLP + totalLPOwned) * price
        //for v1.1
        // require(
        //     vars.TVL == 0 ||
        //         ((MathHelpers.convertFromWad((targetLP + ILPTokenSVS(poolData.poolLPToken).getBalanceOf(user)) * vars.LPPrice)) <=
        //             MathHelpers.convertFromWadPercentage(vars.TVL * poolData.liquidityLimit.maxDepositPercentage)),
        //     Errors.DEPOSIT_LIMIT_REACHED
        // );
        if ((MathHelpers.convertFromWad(targetLP * vars.LPPrice)) > maxStable) {
            vars.LPAmount = MathHelpers.convertToWad(maxStable) / vars.LPPrice;
            vars.stable = maxStable;
        } else {
            vars.LPAmount = targetLP;
            vars.stable = MathHelpers.convertFromWad(targetLP * vars.LPPrice);
        }
        distributeLiquidityToAll(vars.stable, vars.TVLActive, vars.v, addressesRegistry, poolData, subPools);

        emit AddedLiqStable(vars.stable, vars.LPAmount, user);
        IERC20(poolData.stable).safeTransferFrom(user, poolData.poolLPToken, vars.stable);
        ILPTokenSVS(poolData.poolLPToken).mint(user, vars.LPAmount);
        return (vars.stable, vars.LPAmount);
    }

    /**
     * @dev Function to remove liquidity by stable coins
     * @param user The account to remove LP from
     * @param yieldReserve The current reserve deposited in yield generators
     * @param targetLP The amount of LPs to be burned
     * @param minStable The minimum stable tokens to receive
     * @param addressesRegistry the addresses registry used to link the connectors
     * @param poolData The liquidity pool data structure
     * @param subPools The subpools array
     * @param queuedWithdrawals The queued withdrawals
     */
    function removeLiquidityStable(
        address user,
        uint256 yieldReserve,
        uint256 targetLP,
        uint256 minStable,
        address addressesRegistry,
        DataTypes.PoolSVSData storage poolData,
        DataTypes.AMMSubPoolSVS[] storage subPools,
        DataTypes.Queued1155Withdrawals storage queuedWithdrawals
    ) external returns (uint256, uint256) {
        require(user != address(0), Errors.ADDRESS_IS_ZERO);
        require(ILPTokenSVS(poolData.poolLPToken).getBalanceOf(user) >= targetLP, Errors.NOT_ENOUGH_USER_BALANCE);
        require(subPools.length > 0, Errors.NO_SUB_POOL_AVAILABLE);
        DataTypes.LiqLocalVars memory vars;
        (vars.v, vars.TVL, vars.TVLActive, vars.LPPrice) = PoolSVSLogic.calculateLiquidityDetailsIterative(
            addressesRegistry,
            poolData,
            subPools
        );
        //Check how much stablecoins remaining in the pool excluding yield investment
        vars.stableRemaining = IERC20(poolData.stable).balanceOf(poolData.poolLPToken) - yieldReserve;

        //Calculate maximum LP Tokens to remove
        vars.remainingLP = targetLP.min(MathHelpers.convertToWad(vars.stableRemaining) / vars.LPPrice);
        vars.LPAmount = MathHelpers.convertToWad(subPools[0].reserve) / vars.LPPrice;
        if (vars.LPAmount >= vars.remainingLP) {
            vars.remainingLP = 0;
            vars.stable = MathHelpers.convertFromWad(vars.remainingLP * vars.LPPrice);
            subPools[0].reserve -= vars.stable;
            vars.stableTotal += vars.stable;
        } else {
            vars.remainingLP -= vars.LPAmount;
            vars.stableTotal += subPools[0].reserve;
            subPools[0].reserve = 0;
        }
        if (vars.remainingLP > 0) {
            //Repeat due to change in reserves
            (vars.v, vars.TVL, vars.TVLActive, vars.LPPrice) = PoolSVSLogic.calculateLiquidityDetailsIterative(
                addressesRegistry,
                poolData,
                subPools
            );
            //Start at subpool 1
            for (vars.i = 1; vars.i < subPools.length; ++vars.i) {
                if (subPools[vars.i].status) {
                    vars.weighted = vars.remainingLP.min(
                        (targetLP * PoolSVSLogic.calculateTotal(subPools, vars.v, vars.i)) / vars.TVLActive
                    );
                    vars.stable = MathHelpers.convertFromWad(vars.weighted * vars.LPPrice);
                    vars.stable = subPools[vars.i].reserve.min(vars.stable);
                    subPools[vars.i].reserve -= vars.stable;
                    PoolSVSLogic.updatePriceIterative(addressesRegistry, poolData, subPools, vars.i);
                    vars.stableTotal += vars.stable;
                    vars.remainingLP -= vars.weighted;
                }
            }
        }
        //re-use this variable to get the final LP amount
        vars.LPAmount = targetLP - vars.remainingLP - yieldReserve;
        require(vars.stableTotal >= minStable, Errors.LP_VALUE_BELOW_TARGET);
        emit RemovedLiqStable(vars.stableTotal, vars.LPAmount, user, poolData.liquidityLimit.cooldown > 0 ? true : false);
        //If there is a cooldown, then store the stable in an array in the user data to be released later
        if (poolData.liquidityLimit.cooldown == 0) {
            ILPTokenSVS(poolData.poolLPToken).setApproval20(poolData.stable, vars.stableTotal);
            IERC20(poolData.stable).safeTransferFrom(poolData.poolLPToken, user, vars.stableTotal);
        } else {
            DataTypes.Withdraw1155Data storage current = queuedWithdrawals.withdrawals[queuedWithdrawals.nextId];
            current.to = user;
            //Using block.timestamp is safer than block number
            //See: https://ethereum.stackexchange.com/questions/11060/what-is-block-timestamp/11072#11072
            current.unlockTimestamp = block.timestamp + poolData.liquidityLimit.cooldown;
            current.amount = vars.stableTotal;
            ++queuedWithdrawals.nextId;
        }
        ILPTokenSVS(poolData.poolLPToken).burn(user, vars.LPAmount);
        return (vars.stableTotal, vars.LPAmount);
    }

    // /**
    //  * @dev Function to process queued withdraw transactions upto limit and return number of transactions processed
    //  * @notice make it update F if needed for future
    //  * @param limit The number of transactions to process in queue
    //  * @param poolData The liquidity pool data structure
    //  * @param queuedWithdrawals The queued withdrawals
    //  * @return transactions number of transactions processed. 0 = no transactions in queue
    //  */
    // function processWithdrawals(
    //     uint256 limit,
    //     DataTypes.PoolSVSData storage poolData,
    //     DataTypes.Queued1155Withdrawals storage queuedWithdrawals
    // ) external returns (uint256 transactions) {
    //     for (uint256 i; i < limit; ++i) {
    //         DataTypes.Withdraw1155Data storage current = queuedWithdrawals.withdrawals[queuedWithdrawals.headId];
    //         //Using block.timestamp is safer than block number
    //         //See: https://ethereum.stackexchange.com/questions/11060/what-is-block-timestamp/11072#11072
    //         if (current.unlockTimestamp < block.timestamp) break;
    //         if (current.amount > 0) {
    //             ILPTokenSVS(poolData.poolLPToken).setApproval20(poolData.stable, current.amount);
    //             IERC20(poolData.stable).safeTransferFrom(poolData.poolLPToken, current.to, current.amount);
    //         }
    //         for (uint256 j = 0; j < current.shares.length; ++j) {
    //             IERC1155(PoolSVSLogic.getCollectionToken(poolData)).safeTransferFrom(
    //                 poolData.poolLPToken,
    //                 current.to,
    //                 current.shares[j].tokenId,
    //                 current.shares[j].amount,
    //                 ""
    //             );
    //         }
    //         ++transactions;
    //         ++queuedWithdrawals.headId;
    //     }
    //     if (queuedWithdrawals.nextId == queuedWithdrawals.headId) {
    //         queuedWithdrawals.nextId = 0;
    //         queuedWithdrawals.headId = 0;
    //     }
    //     emit WithdrawalsProcessed(msg.sender, transactions);
    // }

    /**
     * @dev Function that returns an array of structures that represent that subpools found that has an array of shares in those subpools and the counter represents the length of the outer and inner arrays
     * @param  params The shares arrays (token ids, amounts) to group
     * @param addressesRegistry the addresses registry used to link the connectors
     * @param poolData The liquidity pool data
     * @param subPools the subpools array of the liquidity pool
     * @return subPoolGroups array of DataTypes.SubPoolGroup output
     * @return counter The counter of array elements used
     */
    function groupBySubpoolDynamic(
        DataTypes.Shares1155Params memory params,
        address addressesRegistry,
        DataTypes.PoolSVSData storage poolData,
        DataTypes.AMMSubPoolSVS[] storage subPools
    ) public view returns (DataTypes.SubPoolGroup[] memory subPoolGroups, uint256 counter) {
        subPoolGroups = new DataTypes.SubPoolGroup[](subPools.length);
        counter = 0;
        DataTypes.LocalGroupVars memory vars;
        //Get the token ids
        if (params.tokenIds.length == 1) {
            counter = 1;
            subPoolGroups = new DataTypes.SubPoolGroup[](1);
            DataTypes.SubPoolCheckerVars memory checkerVars;
            (checkerVars.subPoolIndex, , , , checkerVars.matured) = PoolSVSLogic.checkSubPool(
                params.tokenIds[0],
                addressesRegistry,
                poolData,
                subPools
            );
            require(!checkerVars.matured, Errors.VAULT_SHARE_MATURED);
            subPoolGroups[0] = DataTypes.SubPoolGroup(
                checkerVars.subPoolIndex,
                1,
                params.amounts[0],
                new DataTypes.AMMShare1155[](1),
                vars.cal
            );
            subPoolGroups[0].shares[0] = DataTypes.AMMShare1155(params.tokenIds[0], params.amounts[0]);
        } else {
            //First we create an array of same length of the params and fill it with the token ids, subpool ids and amounts
            vars.paramGroups = new DataTypes.ParamGroup[](params.tokenIds.length);
            for (vars.i; vars.i < params.tokenIds.length; ++vars.i) {
                DataTypes.SubPoolCheckerVars memory checkerVars;
                (checkerVars.subPoolIndex, , , , checkerVars.matured) = PoolSVSLogic.checkSubPool(
                    params.tokenIds[vars.i],
                    addressesRegistry,
                    poolData,
                    subPools
                );
                require(!checkerVars.matured, Errors.VAULT_SHARE_MATURED);
                vars.paramGroups[vars.i].subPoolId = checkerVars.subPoolIndex;
                vars.paramGroups[vars.i].amount = params.amounts[vars.i];
                vars.paramGroups[vars.i].tokenId = params.tokenIds[vars.i];
            }
            //Then we sort the new array using the insertion method
            for (vars.i = 1; vars.i < vars.paramGroups.length; ++vars.i) {
                for (uint j = 0; j < vars.i; ++j)
                    if (vars.paramGroups[vars.i].subPoolId < vars.paramGroups[j].subPoolId) {
                        DataTypes.ParamGroup memory x = vars.paramGroups[vars.i];
                        vars.paramGroups[vars.i] = vars.paramGroups[j];
                        vars.paramGroups[j] = x;
                    }
            }
            //The we iterate last time through the array and construct the subpool group
            for (vars.i = 0; vars.i < vars.paramGroups.length; ++vars.i) {
                if (vars.i == 0 || vars.paramGroups[vars.i].subPoolId != vars.paramGroups[vars.i - 1].subPoolId) {
                    subPoolGroups[counter] = DataTypes.SubPoolGroup(
                        vars.paramGroups[vars.i].subPoolId,
                        0,
                        0,
                        new DataTypes.AMMShare1155[](vars.paramGroups.length),
                        vars.cal
                    );
                    ++counter;
                }
                vars.index = counter - 1;
                subPoolGroups[vars.index].shares[subPoolGroups[vars.index].counter] = DataTypes.AMMShare1155(
                    vars.paramGroups[vars.i].tokenId,
                    vars.paramGroups[vars.i].amount
                );
                subPoolGroups[vars.index].total += vars.paramGroups[vars.i].amount;
                ++subPoolGroups[vars.index].counter;
            }
        }
    }

    /** @dev Get full quotation
     * @param quoteParams the quote params containing the buy/sell flag and the use fee flag
     * @param params The shares arrays (token ids, amounts)
     * @param addressesRegistry the addresses registry used to link the connectors
     * @param poolData The liquidity pool data
     * @param subPools the subpools array of the liquidity pool
     */
    function getQuote(
        DataTypes.QuoteParams calldata quoteParams,
        DataTypes.Shares1155Params calldata params,
        address addressesRegistry,
        DataTypes.PoolSVSData storage poolData,
        DataTypes.AMMSubPoolSVS[] storage subPools
    ) external view returns (DataTypes.Quotation memory quotation) {
        require(params.tokenIds.length == params.amounts.length, Errors.ARRAY_NOT_SAME_LENGTH);
        DataTypes.LocalQuoteVars memory vars;
        quotation.shares = new DataTypes.SharePrice[](params.tokenIds.length);
        //Get the grouped token ids by subpool
        (vars.subPoolGroups, vars.counter) = groupBySubpoolDynamic(params, addressesRegistry, poolData, subPools);
        for (vars.i; vars.i < vars.counter; ++vars.i) {
            vars.currentSubPool = vars.subPoolGroups[vars.i];
            vars.poolId = vars.currentSubPool.id;
            require(subPools[vars.poolId].status, Errors.SUBPOOL_DISABLED);
            //Calculate the value of the shares from its subpool
            vars.currentSubPool.sharesCal = PoolSVSLogic.CalculateShares(
                quoteParams.buy ? DataTypes.OperationType.buyShares : DataTypes.OperationType.sellShares,
                vars.poolId,
                vars.currentSubPool.total,
                quoteParams.useFee,
                addressesRegistry,
                poolData,
                subPools
            );
            for (vars.y = 0; vars.y < vars.currentSubPool.counter; ++vars.y) {
                vars.currentShare = vars.currentSubPool.shares[vars.y];
                require(
                    subPools[vars.poolId].shares[vars.currentShare.tokenId].amount >= vars.currentShare.amount || !quoteParams.buy,
                    Errors.NOT_ENOUGH_SUBPOOL_SHARES
                );
                quotation.shares[vars.counterShares].value = vars.currentShare.amount * vars.currentSubPool.sharesCal.swapPV;
                quotation.shares[vars.counterShares].id = vars.currentShare.tokenId;
                quotation.shares[vars.counterShares].fees = PoolSVSLogic.multiplyFees(
                    vars.subPoolGroups[vars.i].sharesCal.fees,
                    vars.currentShare.amount,
                    vars.currentSubPool.total
                );
                ++vars.counterShares;
            }
            quotation.fees = PoolSVSLogic.addFees(quotation.fees, vars.subPoolGroups[vars.i].sharesCal.fees);
            require(
                subPools[vars.poolId].reserve >= vars.subPoolGroups[vars.i].sharesCal.value || quoteParams.buy,
                Errors.NOT_ENOUGH_SUBPOOL_RESERVE
            );
            quotation.total += vars.subPoolGroups[vars.i].sharesCal.value;
        }
    }

    /** @dev Experimental Function to the swap shares to stablecoins using grouping by subpools
     * @notice subPoolGroupsPointer should be cleared by making it "1" after each iteration of the grouping
     * @param user The user address to transfer the shares from
     * @param  minStable The minimum stablecoins to receive
     * @param  yieldReserve The current reserve in yield contracts
     * @param  params The shares arrays to deduct (token ids, amounts)
     * @param addressesRegistry the addresses registry used to link the connectors
     * @param poolData The pool data including fee configuration
     * @param subPools the subpools array of the liquidity pool
     */
    function swapShares(
        address user,
        uint256 minStable,
        uint256 yieldReserve,
        DataTypes.Shares1155Params memory params,
        address addressesRegistry,
        DataTypes.PoolSVSData storage poolData,
        DataTypes.AMMSubPoolSVS[] storage subPools
    ) external {
        require(params.tokenIds.length == params.amounts.length, Errors.ARRAY_NOT_SAME_LENGTH);

        DataTypes.SwapLocalVars memory vars;
        DataTypes.SubPoolCheckerVars memory checkerVars;
        (vars.subPoolGroups, vars.counter) = groupBySubpoolDynamic(params, addressesRegistry, poolData, subPools);
        //Check how much stablecoins remaining in the pool excluding yield investment
        require(IERC20(poolData.stable).balanceOf(poolData.poolLPToken) - yieldReserve >= minStable, Errors.NOT_ENOUGH_POOL_RESERVE);
        //Get the grouped token ids by subpool
        for (vars.i; vars.i < vars.counter; ++vars.i) {
            vars.currentSubPool = vars.subPoolGroups[vars.i];
            vars.poolId = vars.currentSubPool.id;
            require(
                subPools[vars.poolId].F >= poolData.iterativeLimit.minimumF,
                Errors.SWAPPING_SHARES_TEMPORARY_DISABLED_DUE_TO_LOW_CONDITIONS
            );
            require(subPools[vars.poolId].status, Errors.SUBPOOL_DISABLED);
            //Calculate the value of the shares inside this group
            vars.currentSubPool.sharesCal = PoolSVSLogic.CalculateShares(
                DataTypes.OperationType.sellShares,
                vars.poolId,
                vars.currentSubPool.total,
                true,
                addressesRegistry,
                poolData,
                subPools
            );
            vars.stable =
                vars.currentSubPool.sharesCal.value -
                vars.currentSubPool.sharesCal.fees.royalties -
                vars.currentSubPool.sharesCal.fees.protocolFee;
            //Skip this subpool if there isn't enough
            //The pricing depends on all the shares together, otherwise we need to break them and re-iterate (future feature)
            require(vars.currentSubPool.sharesCal.value <= subPools[vars.poolId].reserve, Errors.NOT_ENOUGH_SUBPOOL_RESERVE);
            require(vars.currentSubPool.sharesCal.value > 0, Errors.SHARES_VALUE_CANNOT_BE_ZERO);
            vars.stableOut += vars.stable;
            //add the total fees for emitting the event
            vars.fees = PoolSVSLogic.addFees(vars.fees, vars.currentSubPool.sharesCal.fees);
            //Update the reserve of stable and shares and F
            subPools[vars.poolId].reserve -= (vars.currentSubPool.sharesCal.value);
            subPools[vars.poolId].totalShares += vars.currentSubPool.total;
            subPools[vars.poolId].F = vars.currentSubPool.sharesCal.F;

            //Recalculate for buying to modify dynamic fees
            vars.currentSubPool.sharesCal = PoolSVSLogic.CalculateShares(
                DataTypes.OperationType.buyShares,
                vars.poolId,
                vars.currentSubPool.total,
                true,
                addressesRegistry,
                poolData,
                subPools
            );
            require(
                vars.stable <
                    vars.currentSubPool.sharesCal.value +
                        vars.currentSubPool.sharesCal.fees.royalties +
                        vars.currentSubPool.sharesCal.fees.protocolFee,
                Errors.TRANSACTION_REJECTED_DUE_TO_CONDITIONS
            );

            //Iterate through the shares inside the Group
            for (vars.y = 0; vars.y < vars.currentSubPool.counter; ++vars.y) {
                vars.currentShare = vars.currentSubPool.shares[vars.y];
                (, , checkerVars.lockupStart, checkerVars.lockupTime, ) = PoolSVSLogic.checkSubPool(
                    vars.currentShare.tokenId,
                    addressesRegistry,
                    poolData,
                    subPools
                );

                PoolSVSLogic.findAndSaveTokenId(
                    vars.currentShare.tokenId,
                    vars.poolId,
                    checkerVars.lockupStart,
                    checkerVars.lockupTime,
                    subPools
                );
                subPools[vars.poolId].shares[vars.currentShare.tokenId].amount += vars.currentShare.amount;
                //Transfer the tokens
                //We cant transfer batch outside the loop since the array of token ids and amounts have a counter after grouping
                //To generate proper token ids and amounts arrays for transfer batch, the groupBySubpoolDynamic will be redesigned and cost more gas
                //Even if grouped and the transfer is outside the current for loop, there is still another for loop due to economy of scale approach
                IERC1155(PoolSVSLogic.getCollectionToken(poolData)).safeTransferFrom(
                    user,
                    poolData.poolLPToken,
                    vars.currentShare.tokenId,
                    vars.currentShare.amount,
                    ""
                );
            }
            PoolSVSLogic.updatePriceIterative(addressesRegistry, poolData, subPools, vars.poolId);
        }
        require(vars.stableOut >= minStable, Errors.SHARES_VALUE_BELOW_TARGET);
        if (vars.stableOut > 0) {
            emit SwappedShares(vars.stableOut, vars.fees, user, vars.subPoolGroups);
            //Add to the balances of the protocol wallet and royalties address
            poolData.fee.protocolBalance += vars.fees.protocolFee;
            poolData.fee.royaltiesBalance += vars.fees.royalties;
            //Transfer the total stable to the user
            ILPTokenSVS(poolData.poolLPToken).setApproval20(poolData.stable, vars.stableOut);
            IERC20(poolData.stable).safeTransferFrom(poolData.poolLPToken, user, vars.stableOut);
        }
    }

    /** @dev Experimental Function to the swap stablecoins to shares using grouping by subpools
     * @param user The user address to deduct stablecoins
     * @param maxStable the maximum stablecoins to deduct
     * @param  params The shares arrays (token ids, amounts)
     * @param addressesRegistry the addresses registry used to link the connectors
     * @param poolData The pool data including fee configuration
     * @param subPools the subpools array of the liquidity pool
     */
    function swapStable(
        address user,
        uint256 maxStable,
        DataTypes.Shares1155Params memory params,
        address addressesRegistry,
        DataTypes.PoolSVSData storage poolData,
        DataTypes.AMMSubPoolSVS[] storage subPools
    ) external {
        require(params.tokenIds.length == params.amounts.length, Errors.ARRAY_NOT_SAME_LENGTH);
        require(IERC20(poolData.stable).allowance(user, address(this)) >= maxStable, Errors.NOT_ENOUGH_APPROVED);
        require(IERC20(poolData.stable).balanceOf(user) >= maxStable, Errors.NOT_ENOUGH_USER_BALANCE);
        DataTypes.SwapLocalVars memory vars;
        vars.remaining = maxStable;
        //Get the grouped token ids by subpool
        (vars.subPoolGroups, vars.counter) = groupBySubpoolDynamic(params, addressesRegistry, poolData, subPools);
        //iterate the subpool groups
        for (vars.i; vars.i < vars.counter; ++vars.i) {
            vars.currentSubPool = vars.subPoolGroups[vars.i];
            vars.poolId = vars.currentSubPool.id;
            require(subPools[vars.poolId].status, Errors.SUBPOOL_DISABLED);
            //Calculate the value of the shares inside this group
            //This requires that the total shares in the subpool >= amount requested or it reverts
            vars.currentSubPool.sharesCal = PoolSVSLogic.CalculateShares(
                DataTypes.OperationType.buyShares,
                vars.poolId,
                vars.currentSubPool.total,
                true,
                addressesRegistry,
                poolData,
                subPools
            );
            //If the value of the shares is higher than the remaining stablecoins to consume, continue the for.
            // Otherwise, we would need to recalculate using the remaining stable
            // It is better to assume that the user approved more than the shares value
            //if (vars.currentSubPool.sharesCal.value + vars.currentSubPool.sharesCal.fees.totalFee > vars.remaining) continue;
            require(
                vars.currentSubPool.sharesCal.value +
                    vars.currentSubPool.sharesCal.fees.royalties +
                    vars.currentSubPool.sharesCal.fees.protocolFee <=
                    vars.remaining,
                Errors.SHARES_VALUE_EXCEEDS_TARGET
            );
            require(vars.currentSubPool.sharesCal.value > 0, Errors.SHARES_VALUE_CANNOT_BE_ZERO);
            vars.remaining -= (vars.currentSubPool.sharesCal.value +
                vars.currentSubPool.sharesCal.fees.royalties +
                vars.currentSubPool.sharesCal.fees.protocolFee);
            //increment the total fees for emitting the event
            vars.fees = PoolSVSLogic.addFees(vars.fees, vars.currentSubPool.sharesCal.fees);
            //Update the reserve of stable and shares and F
            subPools[vars.poolId].reserve += vars.currentSubPool.sharesCal.value;
            subPools[vars.poolId].totalShares -= vars.currentSubPool.total;
            subPools[vars.poolId].F = vars.currentSubPool.sharesCal.F;

            //Recalculate for selling to modify dynamic fees
            vars.currentSubPool.sharesCal = PoolSVSLogic.CalculateShares(
                DataTypes.OperationType.sellShares,
                vars.poolId,
                vars.currentSubPool.total,
                true,
                addressesRegistry,
                poolData,
                subPools
            );
            require(
                vars.currentSubPool.sharesCal.value -
                    vars.currentSubPool.sharesCal.fees.royalties -
                    vars.currentSubPool.sharesCal.fees.protocolFee <
                    vars.stable,
                Errors.TRANSACTION_REJECTED_DUE_TO_CONDITIONS
            );

            //Iterate through all the shares to update their new amounts in the subpool
            for (vars.y = 0; vars.y < vars.currentSubPool.counter; ++vars.y) {
                vars.currentShare = vars.currentSubPool.shares[vars.y];
                require(
                    subPools[vars.poolId].shares[vars.currentShare.tokenId].amount >= vars.currentShare.amount,
                    Errors.NOT_ENOUGH_SUBPOOL_SHARES
                );
                subPools[vars.poolId].shares[vars.currentShare.tokenId].amount -= vars.currentShare.amount;
                if (subPools[vars.poolId].shares[vars.currentShare.tokenId].amount == 0) {
                    subPools[vars.poolId].shares[vars.currentShare.tokenId].start = 0;
                }
                //Transfer the tokens
                //We cant transfer batch outside the loop since the array of token ids and amounts have a counter after grouping
                //To generate proper token ids and amounts arrays for transfer batch, the groupBySubpoolDynamic will be redesigned and cost more gas
                //Even if grouped and the transfer is outside the current for loop, there is still another for loop due to economy of scale approach
                ILPTokenSVS(poolData.poolLPToken).checkApproval1155(poolData.tokens);
                IERC1155(PoolSVSLogic.getCollectionToken(poolData)).safeTransferFrom(
                    poolData.poolLPToken,
                    user,
                    vars.currentShare.tokenId,
                    vars.currentShare.amount,
                    ""
                );
            }
            PoolSVSLogic.updatePriceIterative(addressesRegistry, poolData, subPools, vars.poolId);
        }
        //Add to the balances of the protocol wallet and royalties address
        poolData.fee.protocolBalance += vars.fees.protocolFee;
        poolData.fee.royaltiesBalance += vars.fees.royalties;
        emit SwappedStable(maxStable - vars.remaining, vars.fees, user, vars.subPoolGroups);
        //Transfer the total stable from the user
        IERC20(poolData.stable).safeTransferFrom(user, poolData.poolLPToken, maxStable - vars.remaining);
    }

    /**
     * @dev Function to withdraw fees by a caller that is either the royalties or protocol address
     * @param user The caller
     * @param to The address to send the funds to
     * @param amount The amount to withdraw
     * @param feeType The type of the fees to withdraw
     * @param poolData The pool data
     */
    function withdrawFees(
        address user,
        address to,
        uint256 amount,
        DataTypes.FeeType feeType,
        DataTypes.PoolSVSData storage poolData
    ) external {
        //If withdrawing royalties and the msg.sender matches the royalties address
        if (feeType == DataTypes.FeeType.royalties && user == poolData.fee.royaltiesAddress && amount <= poolData.fee.royaltiesBalance) {
            poolData.fee.royaltiesBalance -= amount;
            emit WithdrawnFees(user, to, amount, "royalties");
            ILPTokenSVS(poolData.poolLPToken).setApproval20(poolData.stable, amount);
            IERC20(poolData.stable).safeTransferFrom(poolData.poolLPToken, to, amount);
        }
        //If withdrawing protocol fees and the msg.sender matches the protocol address
        if (feeType == DataTypes.FeeType.protocol && user == poolData.fee.protocolFeeAddress && amount <= poolData.fee.protocolBalance) {
            poolData.fee.protocolBalance -= amount;
            emit WithdrawnFees(user, to, amount, "protocol");
            ILPTokenSVS(poolData.poolLPToken).setApproval20(poolData.stable, amount);
            IERC20(poolData.stable).safeTransferFrom(poolData.poolLPToken, to, amount);
        }
    }
}

