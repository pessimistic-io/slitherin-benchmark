// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.16;
pragma experimental ABIEncoderV2;

// ==========================================================
// ====================== UniswapAMM ========================
// ==========================================================

// Primary Author(s)
// MAXOS Team: https://maxos.finance/

import "./ISweep.sol";
import "./Owned.sol";
import "./TransferHelper.sol";
import "./ISwapRouter.sol";

contract UniswapAMM is Owned {
    // Core
    ISweep private SWEEP;

    // Uniswap v3
    ISwapRouter public univ3_router;

    constructor(
        address _creator_address,
        address _sweep_contract_address,
        address _uniswap_router_address
    ) Owned(_creator_address) {
        SWEEP = ISweep(_sweep_contract_address);
        univ3_router = ISwapRouter(_uniswap_router_address); //0xE592427A0AEce92De3Edee1F18E0157C05861564
    }

    event Bought(uint256 usdx_amount);
    event Sold(uint256 sweep_amount);

    /* ========== Actions ========== */

    /**
    * @notice Buy Sweep
    * @param _collateral_address Token Address to use for buying sweep.
    * @param _collateral_amount Token Amount.
    * @param _amountOutMin Minimum amount out.
    * @dev Increases the sweep balance and decrease collateral balance.
    */
    function buySweep(address _collateral_address, uint256 _collateral_amount, uint256 _amountOutMin) public returns (uint256 sweep_amount) {
        uint256 sweep_price = SWEEP.amm_price();
        sweep_amount = swapExactInput(_collateral_address, address(SWEEP), _collateral_amount, _amountOutMin);
        SWEEP.refreshTargetPrice(sweep_price);

        emit Bought(sweep_amount);
    }

    /**
    * @notice Sell Sweep
    * @param _collateral_address Token Address to return after selling sweep.
    * @param _sweep_amount Sweep Amount.
    * @param _amountOutMin Minimum amount out.
    * @dev Decreases the sweep balance and increase collateral balance
    */
    function sellSweep(address _collateral_address, uint256 _sweep_amount, uint256 _amountOutMin) public returns (uint256 collateral_amount) {
        uint256 sweep_price = SWEEP.amm_price();
        collateral_amount = swapExactInput(address(SWEEP), _collateral_address, _sweep_amount, _amountOutMin);
        SWEEP.refreshTargetPrice(sweep_price);

        emit Sold(_sweep_amount);
    }

    /**
    * @notice Swap tokenA into tokenB using univ3_router.ExactInputSingle()
    * @param _tokenA Address to in
    * @param _tokenB Address to out
    * @param _amountIn Amount of _tokenA
    * @param _amountOutMin Minimum amount out.
    */
    function swapExactInput(address _tokenA, address _tokenB, uint256 _amountIn, uint256 _amountOutMin) public returns (uint256 amountOut) {
        // Approval
        TransferHelper.safeTransferFrom(_tokenA, msg.sender, address(this), _amountIn);
        TransferHelper.safeApprove(_tokenA, address(univ3_router), _amountIn);

        ISwapRouter.ExactInputSingleParams memory swap_params = ISwapRouter.ExactInputSingleParams({
            tokenIn: _tokenA,
            tokenOut: _tokenB,
            fee: 3000,
            recipient: msg.sender,
            deadline: block.timestamp + 200,
            amountIn: _amountIn,
            amountOutMinimum: _amountOutMin,
            sqrtPriceLimitX96: 0
        });

        amountOut = univ3_router.exactInputSingle(swap_params);
    }

    /**
    * @notice setSweep
    * @param _sweep_address.
    */
    function setSWEEP(address _sweep_address) external onlyOwner {
        SWEEP = ISweep(_sweep_address);
    }
}

