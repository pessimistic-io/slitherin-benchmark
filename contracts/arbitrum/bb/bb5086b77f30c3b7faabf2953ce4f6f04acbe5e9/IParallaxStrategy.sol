//SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "./ITokensRescuer.sol";
import "./IFees.sol";

interface IParallaxStrategy is ITokensRescuer, IFees {
    struct DepositLPs {
        uint256 amount;
        address user;
    }

    struct DepositTokens {
        uint256[] amountsOutMin;
        uint256 amount;
        address user;
    }

    struct SwapNativeTokenAndDeposit {
        uint256[] amountsOutMin;
        address[][] paths;
    }

    struct SwapERC20TokenAndDeposit {
        uint256[] amountsOutMin;
        address[][] paths;
        uint256 amount;
        address token;
        address user;
    }

    struct DepositParams {
        uint256 usdcAmount;
        uint256 usdtAmount;
        uint256 mimAmount;
        uint256 usdcUsdtLPsAmountOutMin;
        uint256 mimUsdcUsdtLPsAmountOutMin;
    }

    struct WithdrawLPs {
        uint256 amount;
        uint256 earned;
        address receiver;
    }

    struct WithdrawTokens {
        uint256[] amountsOutMin;
        uint256 amount;
        uint256 earned;
        address receiver;
    }

    struct WithdrawAndSwapForNativeToken {
        uint256[] amountsOutMin;
        address[][] paths;
        uint256 amount;
        uint256 earned;
        address receiver;
    }

    struct WithdrawAndSwapForERC20Token {
        uint256[] amountsOutMin;
        address[][] paths;
        uint256 amount;
        uint256 earned;
        address token;
        address receiver;
    }

    struct WithdrawParams {
        uint256 amount;
        uint256 actualWithdraw;
        uint256 mimAmountOutMin;
        uint256 usdcUsdtLPsAmountOutMin;
        uint256 usdcAmountOutMin;
        uint256 usdtAmountOutMin;
    }

    function setCompoundMinAmount(uint256 compoundMinAmount) external;

    /**
     * @notice deposits Curve's MIM/USDC-USDT LPs into the vault
     *         deposits these LPs into the Sorbettiere's staking smart-contract.
     *         LP tokens that are depositing must be approved to this contract.
     *         Executes compound before depositing.
     *         Can only be called by the Parallax contact.
     * @param params parameters for deposit.
     *               amount - amount of LP tokens for deposit
     *               user - address of the user
     *               to whose account the deposit will be made
     * @return amount of deposited tokens
     */
    function depositLPs(DepositLPs memory params) external returns (uint256);

    /**
     *  @notice accepts USDC, USDT, and MIM tokens in equal parts.
     *       Provides USDC and USDT tokens
     *       to the Curve's USDC/USDT liquidity pool.
     *       Provides received LPs (from Curve's USDC/USDT liquidity pool)
     *       and MIM tokens to the Curve's MIM/USDC-USDT LP liquidity pool.
     *       Deposits MIM/USDC-USDT LPs into the Sorbettiere's staking
     *       smart-contract. USDC, USDT, and MIM tokens that are depositing
     *       must be approved to this contract.
     *       Executes compound before depositing.
     *       Can only be called by the Parallax contact.
     * @param params parameters for deposit.
     *               amount - must be set in USDC/USDT tokens (with 6 decimals).
     *               MIM token will be charged the same as USDC and USDT
     *               but with 18 decimal places
     *               (18-6=12 additional zeros will be added).
     *               amountsOutMin -  an array of minimum values
     *               that will be received during exchanges,
     *               withdrawals or deposits of liquidity, etc.
     *               All values can be 0 that means
     *               that you agreed with any output value.
     *               For this strategy and this method
     *               it must contain 2 elements:
     *               0 - minimum amount of output USDC/USDT LP tokens
     *               during add liquidity to Curve's USDC/USDT liquidity pool.
     *               1 - minimum amount of output MIM/USDC-USDT LP tokens
     *               during add liquidity to Curve's
     *               MIM/USDC-USDT liquidity pool.
     *               user - address of the user
     *               to whose account the deposit will be made
     * @return amount of deposited tokens
     */
    function depositTokens(
        DepositTokens memory params
    ) external returns (uint256);

    /**
     * @notice accepts ETH token.
     *      Swaps third of it for USDC, third for USDT, and third for MIM tokens
     *      Provides USDC and USDT tokens to the
     *      Curve's USDC/USDT liquidity pool.
     *      Provides received LPs (from Curve's USDC/USDT liquidity pool)
     *      and MIM tokens to the Curve's MIM/USDC-USDT LP liquidity pool.
     *      Deposits MIM/USDC-USDT LPs into the Sorbettiere's
     *      staking smart-contract.
     *      Executes compound before depositing.
     *      Can only be called by the Parallax contact.
     * @param params parameters for deposit.
     *               amountsOutMin -  an array of minimum values
     *               that will be received during exchanges,
     *               withdrawals or deposits of liquidity, etc.
     *               All values can be 0 that means
     *               that you agreed with any output value.
     *               For this strategy and this method
     *               it must contain 5 elements:
     *               0 - minimum amount of output USDC tokens
     *               during swap of ETH tokens to USDC tokens on SushiSwap.
     *               1 - minimum amount of output USDT tokens
     *               during swap of ETH tokens to USDT tokens on SushiSwap.
     *               2 - minimum amount of output MIM tokens
     *               during swap of ETH tokens to MIM tokens on SushiSwap.
     *               3 - minimum amount of output USDC/USDT LP tokens
     *               during add liquidity to Curve's USDC/USDT liquidity pool.
     *               4 - minimum amount of output MIM/USDC-USDT LP tokens
     *               during add liquidity to Curve's MIM/USDC-USDT
     *               liquidity pool.
     *
     *               paths - paths that will be used during swaps.
     *               For this strategy and this method
     *               it must contain 3 elements:
     *               0 - route for swap of ETH tokens to USDC tokens
     *               (e.g.: [WETH, USDC], or [WETH, MIM, USDC]).
     *               The first element must be WETH, the last one USDC.
     *               1 - route for swap of ETH tokens to USDT tokens
     *               (e.g.: [WETH, USDT], or [WETH, MIM, USDT]).
     *               The first element must be WETH, the last one USDT.
     *               2 - route for swap of ETH tokens to MIM tokens
     *               (e.g.: [WETH, MIM], or [WETH, USDC, MIM]).
     *               The first element must be WETH, the last one MIM.
     * @return amount of deposited tokens
     */
    function swapNativeTokenAndDeposit(
        SwapNativeTokenAndDeposit memory params
    ) external payable returns (uint256);

    /**
     * @notice accepts any whitelisted ERC-20 token.
     *      Swaps third of it for USDC, third for USDT, and third for MIM tokens
     *      Provides USDC and USDT tokens
     *      to the Curve's USDC/USDT liquidity pool.
     *      Provides received LPs (from Curve's USDC/USDT liquidity pool)
     *      and MIM tokens to the Curve's MIM/USDC-USDT LP liquidity pool.
     *      After that deposits MIM/USDC-USDT LPs
     *      into the Sorbettiere's staking smart-contract.
     *      ERC-20 token that is depositing must be approved to this contract.
     *      Executes compound before depositing.
     *      Can only be called by the Parallax contact.
     * @param params parameters for deposit.
     *               amount - amount of erc20 tokens for swap and deposit
     *               token - address of erc20 token
     *               amountsOutMin -  an array of minimum values
     *               that will be received during exchanges,
     *               withdrawals or deposits of liquidity, etc.
     *               All values can be 0 that means
     *               that you agreed with any output value.
     *               For this strategy and this method
     *               it must contain 5 elements:
     *               0 - minimum amount of output USDC tokens
     *               during swap of ETH tokens to USDC tokens on SushiSwap.
     *               1 - minimum amount of output USDT tokens
     *               during swap of ETH tokens to USDT tokens on SushiSwap.
     *               2 - minimum amount of output MIM tokens
     *               during swap of ETH tokens to MIM tokens on SushiSwap.
     *               3 - minimum amount of output USDC/USDT LP tokens
     *               during add liquidity to Curve's USDC/USDT liquidity pool.
     *               4 - minimum amount of output MIM/USDC-USDT LP tokens
     *               during add liquidity to Curve's MIM/USDC-USDT
     *               liquidity pool.
     *
     *               paths - paths that will be used during swaps.
     *               For this strategy and this method
     *               it must contain 3 elements:
     *               0 - route for swap of ETH tokens to USDC tokens
     *               (e.g.: [WETH, USDC], or [WETH, MIM, USDC]).
     *               The first element must be WETH, the last one USDC.
     *               1 - route for swap of ETH tokens to USDT tokens
     *               (e.g.: [WETH, USDT], or [WETH, MIM, USDT]).
     *               The first element must be WETH, the last one USDT.
     *               2 - route for swap of ETH tokens to MIM tokens
     *               (e.g.: [WETH, MIM], or [WETH, USDC, MIM]).
     *               The first element must be WETH, the last one MIM.
     *               user - address of the user
     *               to whose account the deposit will be made
     * @return amount of deposited tokens
     */
    function swapERC20TokenAndDeposit(
        SwapERC20TokenAndDeposit memory params
    ) external returns (uint256);

    /**
     * @notice withdraws needed amount of staked Curve's MIM/USDC-USDT LPs
     *      from the Sorbettiere staking smart-contract.
     *      Sends to the user his MIM/USDC-USDT LP tokens
     *      and withdrawal fees to the fees receiver.
     *      Executes compound before withdrawing.
     *      Can only be called by the Parallax contact.
     *  @param params parameters for deposit.
     *                amount - amount of LP tokens to withdraw
     *                receiver - adress of recipient
     *                to whom the assets will be sent
     */
    function withdrawLPs(WithdrawLPs memory params) external;

    /**
     * @notice withdraws needed amount of staked Curve's MIM/USDC-USDT LPs
     *      from the Sorbettiere staking smart-contract.
     *      Then removes the liquidity from the
     *      Curve's MIM/USDC-USDT liquidity pool.
     *      Using received USDC/USDT LPs removes the liquidity
     *      form the Curve's USDC/USDT liquidity pool.
     *      Sends to the user his USDC, USDT, and MIM tokens
     *      and withdrawal fees to the fees receiver.
     *      Executes compound before withdrawing.
     *      Can only be called by the Parallax contact.
     * @param params parameters for deposit.
     *               amount - amount of LP tokens to withdraw
     *               receiver - adress of recipient
     *               to whom the assets will be sent
     *               amountsOutMin - an array of minimum values
     *               that will be received during exchanges, withdrawals
     *               or deposits of liquidity, etc.
     *               All values can be 0 that means
     *               that you agreed with any output value.
     *               For this strategy and this method
     *               it must contain 4 elements:
     *               0 - minimum amount of output MIM tokens during
     *               remove liquidity from Curve's MIM/USDC-USDT liquidity pool.
     *               1 - minimum amount of output USDC/USDT LP tokens during
     *               remove liquidity from Curve's MIM/USDC-USDT liquidity pool.
     *               2 - minimum amount of output USDT tokens during
     *               remove liquidity from Curve's USDC/USDT liquidity pool.
     */
    function withdrawTokens(WithdrawTokens memory params) external;

    /**
     * @notice withdraws needed amount of staked Curve's MIM/USDC-USDT LPs
     *      from the Sorbettiere staking smart-contract.
     *      Then removes the liquidity from the
     *      Curve's MIM/USDC-USDT liquidity pool.
     *      Using received USDC/USDT LPs removes the liquidity
     *      form the Curve's USDC/USDT liquidity pool.
     *      Exchanges all received USDC, USDT, and MIM tokens for ETH token.
     *      Sends to the user his token and withdrawal fees to the fees receiver
     *      Executes compound before withdrawing.
     *      Can only be called by the Parallax contact.
     * @param params parameters for deposit.
     *               amount - amount of LP tokens to withdraw
     *               receiver - adress of recipient
     *               to whom the assets will be sent
     *               amountsOutMin - an array of minimum values
     *               that will be received during exchanges,
     *               withdrawals or deposits of liquidity, etc.
     *               All values can be 0 that means
     *               that you agreed with any output value.
     *               For this strategy and this method
     *               it must contain 4 elements:
     *               0 - minimum amount of output MIM tokens during
     *               remove liquidity from Curve's MIM/USDC-USDT liquidity pool.
     *               1 - minimum amount of output USDC/USDT LP tokens during
     *               remove liquidity from Curve's MIM/USDC-USDT liquidity pool.
     *               2 - minimum amount of output USDC tokens during
     *               remove liquidity from Curve's USDC/USDT liquidity pool.
     *               3 - minimum amount of output USDT tokens during
     *               remove liquidity from Curve's USDC/USDT liquidity pool.
     *               4 - minimum amount of output ETH tokens during
     *               swap of USDC tokens to ETH tokens on SushiSwap.
     *               5 - minimum amount of output ETH tokens during
     *               swap of USDT tokens to ETH tokens on SushiSwap.
     *               6 - minimum amount of output ETH tokens during
     *               swap of MIM tokens to ETH tokens on SushiSwap.
     *
     *               paths - paths that will be used during swaps.
     *               For this strategy and this method
     *               it must contain 3 elements:
     *               0 - route for swap of USDC tokens to ETH tokens
     *               (e.g.: [USDC, WETH], or [USDC, MIM, WETH]).
     *               The first element must be USDC, the last one WETH.
     *               1 - route for swap of USDT tokens to ETH tokens
     *               (e.g.: [USDT, WETH], or [USDT, MIM, WETH]).
     *               The first element must be USDT, the last one WETH.
     *               2 - route for swap of MIM tokens to ETH tokens
     *               (e.g.: [MIM, WETH], or [MIM, USDC, WETH]).
     *               The first element must be MIM, the last one WETH.
     */
    function withdrawAndSwapForNativeToken(
        WithdrawAndSwapForNativeToken memory params
    ) external;

    function withdrawAndSwapForERC20Token(
        WithdrawAndSwapForERC20Token memory params
    ) external;

    /**
     * @notice claims all rewards
     *      from the Sorbettiere's staking smart-contract (in SPELL token).
     *      Then exchanges them for USDC, USDT, and MIM tokens in equal parts.
     *      Adds exchanged tokens to the Curve's liquidity pools
     *      and deposits received LP tokens to increase future rewards.
     *      Can only be called by the Parallax contact.
     * @param amountsOutMin an array of minimum values
     *                      that will be received during exchanges,
     *                      withdrawals or deposits of liquidity, etc.
     *                      All values can be 0 that means
     *                      that you agreed with any output value.
     *                      For this strategy and this method
     *                      it must contain 4 elements:
     *                      0 - minimum amount of output USDC tokens during
     *                      swap of MIM tokens to USDC tokens on SushiSwap.
     *                      1 - minimum amount of output USDT tokens during
     *                      swap of MIM tokens to USDT tokens on SushiSwap.
     *                      2 - minimum amount of output USDC/USDT LP tokens
     *                      during add liquidity to
     *                      Curve's USDC/USDT liquidity pool.
     *                      3 - minimum amount of output MIM/USDC-USDT LP tokens
     *                      during add liquidity to
     *                      Curve's MIM/USDC-USDT liquidity pool.
     * @return received LP tokens from MimUsdcUsdt pool
     */
    function compound(
        uint256[] memory amountsOutMin
    ) external returns (uint256);

    /**
     * @notice Returns the maximum commission values for the current strategy.
     *      Can not be updated after the deployment of the strategy.
     *      Can be called by anyone.
     * @return max fees for this strategy
     */
    function getMaxFees() external view returns (Fees memory);
}

