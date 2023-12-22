// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import {IAddressesRegistry} from "./IAddressesRegistry.sol";
import {DataTypes} from "./DataTypes.sol";

/**
 * @title IMMESVS
 * @author Souq.Finance
 * @notice Defines the interface of the MME for SVS pools with single collection.
 * @notice License: https://souq-exchange.s3.amazonaws.com/LICENSE.md
 */

interface IMMESVS {
    /**
     * @dev Emitted when pool is paused
     * @param admin The admin address
     */
    event PoolPaused(address admin);
    /**
     * @dev Emitted when pool is unpaused
     * @param admin The admin address
     */
    event PoolUnpaused(address admin);

    /**
     * @dev initialize the pool with pool data and the symbol/name of the LP Token
     * @param _poolData The pool data structure
     * @param symbol The symbol of the lp token
     * @param name The name of the lp token
     */
    function initialize(DataTypes.PoolSVSData memory _poolData, string memory symbol, string memory name) external;

    /**
     * @dev Function to pause
     */
    function pause() external;

    /**
     * @dev Function to unpause
     */
    function unpause() external;

    /**
     * @dev Function to get the quote for swapping shares in buy or sell direction
     * @param amounts The amounts of shares to buy or sell
     * @param tokenIds The shares token ids
     * @param buy The directional boolean. If buy direction then true
     * @param useFee the boolean determining whether to use Fee in the calculation or not in case we want to calculate the value of the shares for liquidity
     */
    function getQuote(
        uint256[] memory amounts,
        uint256[] memory tokenIds,
        bool buy,
        bool useFee
    ) external view returns (DataTypes.Quotation memory quotation);

    /**
     * @dev Function to swap stablecoins to shares
     * @param amounts The amounts of token ids outputted
     * @param tokenIds The token ids outputted
     * @param maxStable The maximum amount of stablecoin to be spent
     */
    function swapStable(uint256[] memory amounts, uint256[] memory tokenIds, uint256 maxStable) external;

    /**
     * @dev Function to swap shares to stablecoins
     * @param amounts The amounts of token ids outputted
     * @param tokenIds The token ids outputted
     * @param minStable The minimum stablecoin to receive
     */
    function swapShares(uint256[] memory amounts, uint256[] memory tokenIds, uint256 minStable) external;

    /**
     * @dev Function to get the TVL of the pool in stablecoin
     * @return uint256 The TVL
     */
    function getTVL() external view returns (uint256);

    /**
     * @dev Function to get the TVL of a specific sub pool
     * @param id The id of the sub pool
     * @return DataTypes.AMMSubPoolSVSDetails object
     */
    function getPool(uint256 id) external view returns (DataTypes.AMMSubPoolSVSDetails memory);

    /**
     * @dev Function to get the total value of a specific subpool
     * @param subPoolId The id of the sub pool
     * @return uint256 the subpool total value
     */
    function getSubPoolTotal(uint256 subPoolId) external view returns (uint256);

    /**
     * @dev Function to add liquidity using Stable coins
     * @param targetLP The amount of target LPs outputted
     * @param _maxStable The amount of maximum stablecoins to be spent
     **/
    function addLiquidityStable(uint256 targetLP, uint256 _maxStable) external;

    /**
     * @dev Function to remove liquidity by stable coins
     * @param targetLP The amount of LPs to be burned
     * @param minStable The minimum stable tokens to receive
     */
    function removeLiquidityStable(uint256 targetLP, uint256 minStable) external;

    // /**
    //  * @dev Function to process all queued transactions upto limit
    //  * @param limit The number of transactions to process
    //  * @return uint256 The number of transactions processed
    //  */
    // function processWithdrawals(uint256 limit) external returns (uint256);

    /**
     * @dev Function to get the LP token address
     * @return address The address
     */
    function getLPToken() external view returns (address);

    /**
     * @dev Function to get the LP token price
     * @return uint256 The price
     */
    function getLPPrice() external view returns (uint256);

    /**
     * @dev Function to get amount of a specific token id available in the pool
     * @param tokenId The token id
     * @return uint256 The amount
     */
    function getTokenIdAvailable(uint256 tokenId) external view returns (uint256);

    /**
     * @dev Function that returns the subpool ids of the given token ids
     * @param tokenIds The address of the pool
     * @return subPools array of the subpool ids
     */
    function getSubPools(uint256[] memory tokenIds) external view returns (uint256[] memory);

    /**
     * @dev Function that deposits the initial liquidity to specific subpool
     * @param tokenIds The token ids array of the shares to deposit
     * @param amounts The amounts array of the shares to deposit
     * @param stableIn The stablecoins amount to deposit
     * @param subPoolId The sub pool id
     */
    function depositInitial(uint256[] memory tokenIds, uint256[] memory amounts, uint256 stableIn, uint256 subPoolId) external;

    /**
     * @dev Function to add a new sub pool
     * @param f The initial F value of the sub pool
     * @param maturity The initial maturity time of the sub pool
     * @param lockupTime The initial lockup Time of the sub pool
     */
    function addSubPool(uint256 f, uint256 maturity, uint256 lockupTime) external;

    /**
     * @dev Function to move enable or disable specific subpools by ids
     * @param subPoolIds The sub pools ids array
     * @param _newStatus The new status, enabled=true or disabled=false
     */
    function changeSubPoolStatus(uint256[] calldata subPoolIds, bool _newStatus) external;

    /**
     * @dev Function to move reserves between subpools
     * @param moverId The sub pool that will move the funds from
     * @param movedId The id of the sub pool that will move the funds to
     * @param amount The amount to move
     */
    function moveReserve(uint256 moverId, uint256 movedId, uint256 amount) external;

    /**
     * @dev Function to rescue and send ERC20 tokens (different than the tokens used by the pool) to a receiver called by the admin
     * @param token The address of the token contract
     * @param amount The amount of tokens
     * @param receiver The address of the receiver
     */
    function RescueTokens(address token, uint256 amount, address receiver) external;

    /**
     * @dev Function to withdraw fees by a caller that is either the royalties or protocol address
     * @param to The address to send the funds to
     * @param amount The amount to withdraw
     * @param feeType The type of the fees to withdraw
     */
    function WithdrawFees(address to, uint256 amount, DataTypes.FeeType feeType) external;

    /**
     * @dev Function that updates the max maturity range between subpools and re orders the subpools and/or creates more
     * @param f The f of the new pools to be created
     * @param newMaxMaturityRange The new max maturity Range
     */
    function updateMaxMaturityRange(uint256 f, uint256 newMaxMaturityRange) external;

    /**
     * @dev Function to get all the matured shares
     * @return array of DataTypes.VaultSharesReturn which contains the id and amount
     */
    function getMatureShares() external view returns (DataTypes.VaultSharesReturn[] memory);

    /**
     * @dev Function to move all mature shares to the maturity subpool maxed by maxTrancheCount
     * @param maxTrancheCount The max count of token ids to move
     * @return trancheCount amount of token ids moved (can be different than the max)
     */
    function moveMatureShares(uint256 maxTrancheCount) external returns (uint256 trancheCount);

    /**
     * @dev Function to move mature shares by selected token ids and amounts
     * @param tranches The array of token ids to move
     * @param amounts The array of amounts to move
     * @return trancheCount amount of token ids moved (can be different than the tranches array length)
     */
    function moveMatureSharesList(uint256[] memory tranches, uint256[] memory amounts) external returns (uint256 trancheCount);

    /**
     * @dev Function to clean all mature subpools and change the starting index
     */
    function cleanMatureSubPools() external;

    /**
     * @dev Function to redeem all the mature shares from the maturity subpool maxed by maxTrancheCount
     * @param maxTrancheCount The max count of token ids to redeem
     * @return trancheCount amount of token ids redeemed (can be different than the max)
     */
    function redeemMatureShares(uint256 maxTrancheCount) external returns (uint256 trancheCount);


    /**
     * @dev Function to distribute the reserve in subpool 0 (maturity) to all active subpools by weight
     */
    function redistrubteLiquidity() external;

    /**
     * @dev Function to set the Pool Data
     * @param _newPoolData the new pooldata struct
     */
    function setPoolData(DataTypes.PoolSVSData calldata _newPoolData) external;

    // /**
    //  * @dev Function to change the lockup times of the subpools to fit the vault
    //  * @param lastLockupTimes The last lockup times for comparison
    //  */
    // function changeLockupTimes(uint256[] memory lastLockupTimes) external;

    /**
     * @dev Function to return the count of subpools created
     * @return count The count
     */
    function getSubPoolsCount() external view returns (uint256 count);
}

