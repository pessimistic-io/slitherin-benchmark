// SPDX-License-Identifier: BUSDL-2.1
pragma solidity 0.6.11;

import {SafeMath} from "./math_SafeMath.sol";
import {IERC20} from "./ERC20_IERC20.sol";

/**
 * @notice deposit contract used for pools such as Compound and USDT
 */
interface IDepositZap3 {
    // solhint-disable-next-line
    function underlying_coins(int128 coin) external view returns (address);

    /**
     * @dev the number of coins is hard-coded in curve contracts
     */
    // solhint-disable-next-line
    function add_liquidity(uint256[3] memory amounts, uint256 min_mint_amount)
        external;

    /**
     * @dev the number of coins is hard-coded in curve contracts
     */
    // solhint-disable-next-line
    function remove_liquidity_one_coin(
        uint256 _amount,
        int128 i,
        uint256 minAmount
    ) external;

    function curve() external view returns (address);
}

