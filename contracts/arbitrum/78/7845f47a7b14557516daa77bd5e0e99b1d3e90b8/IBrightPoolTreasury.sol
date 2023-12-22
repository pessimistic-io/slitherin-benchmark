// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./IERC20.sol";
import "./IBrightPoolConsumer.sol";
import "./IBrightPoolExchangeable.sol";

/**
 * @dev An abstract class defining treasury methods
 */
interface IBrightPoolTreasury is IBrightPoolExchangeable, IBrightPoolConsumer {
    /**
     * @dev Method returns balance of given token or coin.
     *
     * @param token_ The token address to check balance of or 0 to check native coin balance
     *
     * @return The balance of requested token or coin
     */
    function balanceOf(IERC20 token_) external view returns (uint256);

    /**
     * @dev The method checking if given affiliate ID pays in BRI
     *
     * @param id_ The id of the affiliate program
     *
     * @return True if affiliate program pays in BRI, false otherwise
     */
    function isBRIAffiliate(uint256 id_) external view returns (bool);

    /**
     * @dev The method returning the amount of the reward for affiliate
     *
     * @param id_ The id of the affiliate
     * @param amount_ The amount of the original transaction
     *
     * @return The amount to be paid as a reward
     */
    function rewardForAffiliate(uint256 id_, uint256 amount_) external view returns (uint256);
}

