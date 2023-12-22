// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import {DataTypes} from "./DataTypes.sol";
import {Math} from "./Math.sol";
import {Errors} from "./Errors.sol";
import {PoolSVSLogic} from "./PoolSVSLogic.sol";
import {ILPTokenSVS} from "./ILPTokenSVS.sol";
import {IConnectorRouter} from "./IConnectorRouter.sol";
import {IExchangeSwapWithOutQuote} from "./IExchangeSwapWithOutQuote.sol";
import {IAddressesRegistry} from "./IAddressesRegistry.sol";
import {IERC20Extended} from "./IERC20Extended.sol";
import {ISVS} from "./ISVS.sol";
import {IVault1155} from "./IVault1155.sol";

/**
 * @title library for maturity logic functions for the SVS Pools with single collection
 * @author Souq.Finance
 * @notice License: https://souq-exchange.s3.amazonaws.com/LICENSE.md
 */

library MaturitySVSLogic {
    using Math for uint256;
    uint256 public constant MAX_ACTIVE_VAULT_SHARES = 10000;
    /**
     * @dev Emitted when the max maturity range between subpools is updated and re ordered the subpools
     * @param admin The admin that executed the function
     * @param newMaxMaturityRange The new max maturity Range
     */
    event UpdatedMaxMaturityRange(address admin, uint256 newMaxMaturityRange);
    /**
     * @dev Emitted when all mature shares are moved to the maturity subpool maxed by maxTrancheCount
     * @param admin The admin that executed the function
     * @param trancheCount amount of token ids moved (can be different than the max)
     */
    event MovedMatureShares(address admin, uint256 trancheCount);
    /**
     * @dev Emitted when mature shares are moved to the maturity subpool specified by arrays of token ids and amounts
     * @param admin The admin that executed the function
     * @param trancheCount amount of token ids moved (can be different than the max)
     */
    event MovedMatureSharesList(address admin, uint256 trancheCount);
    /**
     * @dev Emitted when the mature subpools are emptied and possible change made to the starting index
     * @param admin The admin that executed the function
     * @param cleaned amount of subpools cleaned
     */
    event CleanedMatureSubPools(address admin, uint256 cleaned);
    /**
     * @dev Emitted when all mature shares are redeemed from the maturity subpool maxed by maxTrancheCount
     * @param admin The admin that executed the function
     * @param trancheCount amount of token ids redeemed (can be different than the max)
     */
    event RedeemedMatureShares(address admin, uint256 trancheCount);

    /**
     * @dev Function that updates the max maturity range between subpools and re orders the subpools
     * @param f The f of the created subpools if any
     * @param newMaxMaturityRange The new max maturity Range
     * @param addressesRegistry the addresses registry used to link the connectors
     * @param poolData The pool data
     * @param subPools the subpools array
     */
    function updateMaxMaturityRange(
        uint256 f,
        uint256 newMaxMaturityRange,
        address addressesRegistry,
        DataTypes.PoolSVSData storage poolData,
        DataTypes.AMMSubPoolSVS[] storage subPools
    ) external {
        require(newMaxMaturityRange > 0, Errors.VALUE_CANNOT_BE_ZERO);
        uint256[] memory lockupTimes = PoolSVSLogic.getCollectionConnector(addressesRegistry, poolData).getLockupTimes(poolData.tokens[0]);
        uint256 currentStart = subPools[poolData.firstActivePool].start;
        //First run to modify all the starts in the new sequence
        for (uint256 i = poolData.firstActivePool + 1; i < subPools.length; i++) {
            DataTypes.AMMSubPoolSVS storage currentSubPool = subPools[i];
            //It iterates till it finds the group of subpools that have a different start
            if (currentSubPool.start != currentStart) {
                for (uint256 j; j < lockupTimes.length; ++j) {
                    if (i + j < subPools.length) {
                        subPools[i + j].start = currentStart + newMaxMaturityRange;
                    }
                }
                currentStart += newMaxMaturityRange;
            }
        }
        poolData.maxMaturityRange = newMaxMaturityRange;
        //Second run is to re-arrange the token ids in their proper subpool
        for (uint256 i = poolData.firstActivePool; i < subPools.length; i++) {
            DataTypes.AMMSubPoolSVS storage currentSubPool = subPools[i];
            for (uint256 j; j < subPools[i].tokenIds.length; ++j) {
                DataTypes.AMMShareSVS storage currentShare = currentSubPool.shares[subPools[i].tokenIds[j]];
                if (currentShare.start > currentSubPool.start + newMaxMaturityRange || currentShare.start < currentSubPool.start) {
                    bool found;
                    uint256 newSubPoolId;
                    (newSubPoolId, found, , , ) = PoolSVSLogic.checkSubPool(subPools[i].tokenIds[j], addressesRegistry, poolData, subPools);
                    if (!found) {
                        PoolSVSLogic.addSubPoolsAuto(f, currentShare.start, addressesRegistry, poolData, subPools);
                    }
                    (newSubPoolId, found, , , ) = PoolSVSLogic.checkSubPool(subPools[i].tokenIds[j], addressesRegistry, poolData, subPools);
                    subPools[newSubPoolId].totalShares += currentShare.amount;
                    currentSubPool.totalShares -= currentShare.amount;
                    subPools[newSubPoolId].shares[subPools[i].tokenIds[j]].amount = currentShare.amount;
                    subPools[newSubPoolId].shares[subPools[i].tokenIds[j]].start = currentShare.start;
                    PoolSVSLogic.findAndSaveTokenId(
                        subPools[i].tokenIds[j],
                        newSubPoolId,
                        currentShare.start,
                        currentShare.lockupTime,
                        subPools
                    );
                    currentShare.start = 0;
                    currentShare.amount = 0;
                }
            }
            PoolSVSLogic.updatePriceIterative(addressesRegistry, poolData, subPools, i);
        }
        emit UpdatedMaxMaturityRange(msg.sender, newMaxMaturityRange);
    }

    /**
     * @dev Function to get all the matured shares
     * @param poolData The pool data
     * @param subPools The subpools array
     * @return sharesReturn array of DataTypes.VaultSharesReturn which contains the token id and amount
     */
    function getMatureShares(
        DataTypes.PoolSVSData storage poolData,
        DataTypes.AMMSubPoolSVS[] storage subPools
    ) external view returns (DataTypes.VaultSharesReturn[] memory sharesReturn) {
        DataTypes.VaultSharesReturn[] memory vars = new DataTypes.VaultSharesReturn[](MAX_ACTIVE_VAULT_SHARES);
        uint256 counter;
        for (uint256 i = poolData.firstActivePool; i < subPools.length; ++i) {
            for (uint256 j; j < subPools[i].tokenIds.length; ++j) {
                if (
                    subPools[i].shares[subPools[i].tokenIds[j]].start + subPools[i].shares[subPools[i].tokenIds[j]].lockupTime <=
                    block.timestamp
                ) {
                    vars[counter] = DataTypes.VaultSharesReturn(
                        subPools[i].tokenIds[j],
                        subPools[i].shares[subPools[i].tokenIds[j]].amount
                    );
                    ++counter;
                }
            }
        }
        sharesReturn = new DataTypes.VaultSharesReturn[](counter);
        for (uint256 i; i < counter; ++i) {
            sharesReturn[i] = vars[i];
        }
    }

    /**
     * @dev Function to move all mature shares to the maturity subpool maxed by maxTrancheCount
     * @param addressesRegistry the addresses registry used to link the connectors
     * @param poolData The pool data
     * @param subPools The subpools array
     * @param maxTrancheCount The max count of token ids to move
     * @return trancheCount amount of token ids moved (can be different than the max)
     */
    function moveMatureShares(
        address addressesRegistry,
        DataTypes.PoolSVSData storage poolData,
        DataTypes.AMMSubPoolSVS[] storage subPools,
        uint256 maxTrancheCount
    ) external returns (uint256 trancheCount) {
        for (uint256 i = poolData.firstActivePool; i < subPools.length; ++i) {
            for (uint256 j; j < subPools[i].tokenIds.length; ++j) {
                if (
                    subPools[i].shares[subPools[i].tokenIds[j]].start + subPools[i].shares[subPools[i].tokenIds[j]].lockupTime <=
                    block.timestamp
                ) {
                    PoolSVSLogic.findAndSaveTokenId(
                        subPools[i].tokenIds[j],
                        0,
                        subPools[i].shares[subPools[i].tokenIds[j]].start,
                        subPools[i].shares[subPools[i].tokenIds[j]].lockupTime,
                        subPools
                    );
                    subPools[0].shares[subPools[i].tokenIds[j]].amount += subPools[i].shares[subPools[i].tokenIds[j]].amount;
                    subPools[0].totalShares += subPools[i].shares[subPools[i].tokenIds[j]].amount;
                    subPools[i].totalShares -= subPools[i].shares[subPools[i].tokenIds[j]].amount;
                    subPools[i].shares[subPools[i].tokenIds[j]].amount = 0;
                    ++trancheCount;
                    if (trancheCount == maxTrancheCount) break;
                }
            }
            PoolSVSLogic.updatePriceIterative(addressesRegistry, poolData, subPools, i);
        }
        emit MovedMatureShares(msg.sender, trancheCount);
    }

    /**
     * @dev Function to move mature shares by selected token ids and amounts
     * @param addressesRegistry the addresses registry used to link the connectors
     * @param poolData The pool data
     * @param subPools The subpools array
     * @param tranches The array of token ids to move
     * @param amounts The array of amounts to move
     * @return trancheCount amount of token ids moved (can be different than the tranches array length)
     */
    function moveMatureSharesList(
        address addressesRegistry,
        DataTypes.PoolSVSData storage poolData,
        DataTypes.AMMSubPoolSVS[] storage subPools,
        uint256[] memory tranches,
        uint256[] memory amounts
    ) external returns (uint256 trancheCount) {
        //If subpool is empty, delete its array and make status = false
        require(tranches.length == amounts.length, Errors.ARRAY_NOT_SAME_LENGTH);
        uint256 subPoolIndex;
        for (uint256 i; i < tranches.length; ++i) {
            (subPoolIndex, , , , ) = PoolSVSLogic.checkSubPool(tranches[i], addressesRegistry, poolData, subPools);
            if (
                subPoolIndex != 0 &&
                subPools[subPoolIndex].shares[tranches[i]].start + subPools[subPoolIndex].shares[tranches[i]].lockupTime <= block.timestamp
            ) {
                require(subPools[subPoolIndex].shares[tranches[i]].amount >= amounts[i], Errors.NOT_ENOUGH_SUBPOOL_SHARES);
                subPools[subPoolIndex].shares[tranches[i]].amount -= amounts[i];
                subPools[0].shares[tranches[i]].amount += amounts[i];
                subPools[subPoolIndex].totalShares -= amounts[i];
                subPools[0].totalShares += amounts[i];
                PoolSVSLogic.findAndSaveTokenId(
                    tranches[i],
                    0,
                    subPools[subPoolIndex].shares[tranches[i]].start,
                    subPools[subPoolIndex].shares[tranches[i]].lockupTime,
                    subPools
                );
                ++trancheCount;
                PoolSVSLogic.updatePriceIterative(addressesRegistry, poolData, subPools, subPoolIndex);
            }
        }
        emit MovedMatureSharesList(msg.sender, trancheCount);
    }

    /**
     * @dev Function to clean all mature subpools and change the starting index
     * @param poolData The pool data
     * @param subPools The subpools array
     */
    function cleanMatureSubPools(DataTypes.PoolSVSData storage poolData, DataTypes.AMMSubPoolSVS[] storage subPools) external {
        uint256 newFirstActive = poolData.firstActivePool;
        uint256 cleaned;
        for (uint256 i = poolData.firstActivePool; i < subPools.length; ++i) {
            bool allMature = true;
            for (uint256 j; j < subPools[i].tokenIds.length; ++j) {
                if (
                    subPools[i].shares[subPools[i].tokenIds[j]].start + subPools[i].shares[subPools[i].tokenIds[j]].lockupTime >
                    block.timestamp
                ) {
                    allMature = false;
                }
            }
            if (allMature && (subPools[i].start + poolData.maxMaturityRange) <= block.timestamp) {
                subPools[i].status = false;
                subPools[i].start = 0;
                delete subPools[i].tokenIds;
                ++cleaned;
                //increment the new first active if the lowest is cleaned
                if (i == (newFirstActive + 1)) {
                    ++newFirstActive;
                }
            }
        }
        poolData.firstActivePool = newFirstActive;
        emit CleanedMatureSubPools(msg.sender, cleaned);
    }

    ///TODO: integrate with the batch if possible
    /**
     * @dev Function to redeem all the mature shares from the maturity subpool maxed by maxTrancheCount
     * @param addressesRegistry the addresses registry used to link the connectors
     * @param poolData The pool data
     * @param subPools The subpools array
     * @param maxTrancheCount The max count of token ids to redeem
     * @return trancheCount amount of token ids redeemed (can be different than the max)
     */
    function redeemMatureShares(
        address addressesRegistry,
        DataTypes.PoolSVSData storage poolData,
        DataTypes.AMMSubPoolSVS[] storage subPools,
        uint256 maxTrancheCount
    ) external returns (uint256 trancheCount) {
        uint256 tokenId;
        //If subpool is empty, delete its array
        for (uint256 i; i < subPools[0].tokenIds.length; ++i) {
            tokenId = subPools[0].tokenIds[i];
            subPools[0].shares[tokenId].amount = 0;
            ++trancheCount;
            if (trancheCount == maxTrancheCount) break;
        }
        emit RedeemedMatureShares(msg.sender, trancheCount);
        uint256 initial = IERC20Extended(poolData.stable).balanceOf(address(this));
        swapVITs(addressesRegistry, poolData);
        uint256 redeemed = IERC20Extended(poolData.stable).balanceOf(address(this)) - initial;
        subPools[0].reserve += redeemed;

        //If all the token ids were redeemed, empty the array.
        //Otherwise move the the values by index lower and then pop the array to remove the last elements moved
        if (subPools[0].tokenIds.length <= trancheCount) {
            delete subPools[0].tokenIds;
        } else {
            for (uint i = trancheCount; i < subPools[0].tokenIds.length; i++) {
                subPools[0].tokenIds[i - trancheCount] = subPools[0].tokenIds[i];
            }
            // Remove the trancheCount elements using a separate loop
            for (uint i = 0; i < trancheCount; i++) {
                subPools[0].tokenIds.pop();
            }
        }
        IERC20Extended(poolData.stable).transfer(poolData.poolLPToken, redeemed);
    }

    /**
     * @dev Function to swap all available VITs to stablecoin
     * @param addressesRegistry the addresses registry used to link the connectors
     * @param poolData The pool data
     */
    function swapVITs(address addressesRegistry, DataTypes.PoolSVSData storage poolData) public {
        address[] memory VITs;
        (VITs, ) = PoolSVSLogic.getCollectionConnector(addressesRegistry, poolData).getVITs(poolData.tokens[0]);
        for (uint i; i < VITs.length; ++i) {
            ILPTokenSVS(poolData.poolLPToken).setApproval20(VITs[i], IERC20Extended(VITs[i]).balanceOf(address(poolData.poolLPToken)));
            IERC20Extended(VITs[i]).transferFrom(
                poolData.poolLPToken,
                address(this),
                IERC20Extended(VITs[i]).balanceOf(address(poolData.poolLPToken))
            );
            if (IERC20Extended(VITs[i]).balanceOf(address(this)) > 0) {
                exchangeSwap(addressesRegistry, poolData.stable, IERC20Extended(VITs[i]).balanceOf(address(this)), VITs[i]);
            }
        }
    }

    /**
     * @dev Function to swap a certain token using its exchange and 2% max slippage on the quote
     * @param addressesRegistry the addresses registry used to link the connectors
     * @param stable The stablecoin address
     * @param amountPerSwap The amount to swap
     * @param VIT The swappable token address
     */
    function exchangeSwap(address addressesRegistry, address stable, uint256 amountPerSwap, address VIT) public {
        address exchangeSwapContract = IConnectorRouter(IAddressesRegistry(addressesRegistry).getConnectorsRouter()).getSwapContract(VIT);
        IERC20Extended(VIT).approve(exchangeSwapContract, amountPerSwap);
        IExchangeSwapWithOutQuote(exchangeSwapContract).swap(
            VIT,
            stable,
            amountPerSwap,
            (IExchangeSwapWithOutQuote(exchangeSwapContract).getQuoteIn(VIT, stable, amountPerSwap) * 98) / 100
        );
    }


    /**
     * @dev Function to change the lockup times of the subpools to fit the vault
     * @param addressesRegistry the addresses registry used to link the connectors
     * @param poolData The pool data
     * @param subPools The subpools array
     * @param lastLockupTimes The last lockup times for comparison
     */
    function changeLockupTimes(
        address addressesRegistry,
        DataTypes.PoolSVSData storage poolData,
        DataTypes.AMMSubPoolSVS[] storage subPools,
        uint256[] memory lastLockupTimes
    ) external {
        uint256[] memory lockupTimes = PoolSVSLogic.getCollectionConnector(addressesRegistry, poolData).getLockupTimes(poolData.tokens[0]);
        for (uint256 i = poolData.firstActivePool; i < subPools.length; ++i) {
            uint256 newLockupTime;
            uint256 lastLockupTime;
            for (uint256 j; j < lastLockupTimes.length; ++j) {
                if(subPools[i].lockupTime == lastLockupTimes[j])
                {
                    lastLockupTime = lastLockupTimes[j];
                    newLockupTime = lockupTimes[j];
                    break;
                }
            }
            subPools[i].lockupTime = newLockupTime;
            for (uint256 j; j < subPools[i].tokenIds.length; ++j) {
                subPools[i].shares[subPools[i].tokenIds[j]].lockupTime = newLockupTime;
            }
        }
    }
}

