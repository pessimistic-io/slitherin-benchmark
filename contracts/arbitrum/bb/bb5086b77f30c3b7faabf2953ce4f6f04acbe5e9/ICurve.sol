//SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "./IERC20.sol";

interface ICurve is IERC20 {
    /**
     * @notice Wrap underlying coins and deposit them in the pool
     * @param amounts List of amounts of underlying coins to deposit
     * @param minMintAmount Minimum amount of LP tokens to mint from the
     *                      deposit
     * @return Amount of LP tokens received by depositing
     **/
    function add_liquidity(
        uint256[2] calldata amounts,
        uint256 minMintAmount
    ) external returns (uint256);

    /**
     * @notice Withdraw and unwrap coins from the pool
     * @dev Withdrawal amounts are based on current deposit ratios
     * @param amount Quantity of LP tokens to burn in the withdrawal
     * @param minAmounts Minimum amounts of underlying coins to receive
     * @return List of amounts of underlying coins that were withdrawn
     **/
    function remove_liquidity(
        uint256 amount,
        uint256[2] calldata minAmounts
    ) external returns (uint256[2] memory);

    /**
     * @notice Calculate addition or reduction in token supply from a deposit
     *         or withdrawal
     * @dev This calculation accounts for slippage, but not fees.
     *      Needed to prevent front-running, not for precise calculations!
     * @param amounts Amount of each underlying coin being deposited
     * @param isDeposit set True for deposits, False for withdrawals
     * @return Expected amount of LP tokens received
     **/
    function calc_token_amount(
        uint256[2] calldata amounts,
        bool isDeposit
    ) external view returns (uint256);
}

