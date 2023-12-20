// SPDX-License-Identifier: BUSDL-1.1
pragma solidity 0.6.11;

import {SafeMath} from "./vendor_SafeMath.sol";
import {IERC20} from "./IERC20.sol";

/**
 * @notice the stablecoin pool contract
 */
interface IOldStableSwap4 {
    function balances(int128 coin) external view returns (uint256);

    function coins(int128 coin) external view returns (address);

    /**
     * @dev the number of coins is hard-coded in curve contracts
     */
    // solhint-disable-next-line
    function add_liquidity(uint256[4] memory amounts, uint256 min_mint_amount)
        external;

    /**
     * @dev the number of coins is hard-coded in curve contracts
     */
    // solhint-disable-next-line
    function remove_liquidity(uint256 _amount, uint256[4] memory min_amounts)
        external;

    /// @dev need this due to lack of `remove_liquidity_one_coin`
    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy // solhint-disable-line func-param-name-mixedcase
    ) external;

    // solhint-disable-next-line
    function get_virtual_price() external view returns (uint256);
}

