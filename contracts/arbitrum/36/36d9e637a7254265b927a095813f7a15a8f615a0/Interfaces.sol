// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;
import { IERC20 } from "./DefinitiveAssets.sol";

// https://github.com/hop-protocol/contracts/blob/master/contracts/saddle/interfaces/ISwap.sol
// https://arbiscan.io/address/0xb67c014fa700e69681a673876eb8bafaa36bff71#code
interface ISwapHop {
    function calculateRemoveLiquidityOneToken(
        uint256 tokenAmount,
        uint8 tokenIndex
    ) external view returns (uint256 availableTokenAmount);

    /**
     * @notice adds liquidity to a pool
     *
     * @param amounts       amounts of each token to add liquidity
     * @param minToMint     minimum amount of LP tokens to receive back
     * @param deadline      block.timestamp to complete by
     * @return uint256      amount of LP tokens minted
     */
    function addLiquidity(uint256[] calldata amounts, uint256 minToMint, uint256 deadline) external returns (uint256);

    /**
     * @notice remove liquidity from hop pool
     *
     * @param tokenAmount    total number of tokens to remove from liquidity
     * @param tokenIndex     index of token
     * @param minAmount      minimum amount of each tokens to receive
     * @param deadline       block.timestamp to complete by
     * @return uint256      amount of tokens received
     *
     */
    function removeLiquidityOneToken(
        uint256 tokenAmount,
        uint8 tokenIndex,
        uint256 minAmount,
        uint256 deadline
    ) external returns (uint256);

    /**
     * @notice remove liquidity from hop pool
     *
     * @param amount        total number of tokens to remove from liquidity
     * @param minAmounts[]  minimum amount of each token to receive
     * @param deadline      block.timestamp to complete by
     * @return uint256[]      amount of each token received
     *
     */
    function removeLiquidity(
        uint256 amount,
        uint256[] calldata minAmounts,
        uint256 deadline
    ) external returns (uint256[] memory);
}

// https://arbiscan.io/address/0xb0cabfe930642ad3e7decdc741884d8c3f7ebc70#code
interface IStakingRewards {
    /**
     * @dev returns address of token used for rewarding stakers
     *
     * @return IERC20
     */
    function rewardsToken() external view returns (IERC20);

    /**
     * @dev Returns the amount of tokens staked by `account`.
     *
     * @return uint256      staked balance of `account`
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @notice farms the staked rewards (usually HOP token)
     */
    function getReward() external;

    /**
     * @notice returns the number of pending reward tokens for `account`
     *
     * @param account          address to check rewards for
     * @return uint256     amount of tokens claimable
     */
    function earned(address account) external view returns (uint256);

    /**
     * @notice stakes the amount of token into the rewards contract
     *
     * @param amount        number of LP tokens to stake
     */
    function stake(uint256 amount) external;

    /**
     * @notice unstakes entire stake and claims rewards
     */
    function exit() external;

    /**
     * @notice unstake a certain amount of LP tokens
     *
     * @param amount        number of LP tokens to unstake
     */
    function withdraw(uint256 amount) external;
}

