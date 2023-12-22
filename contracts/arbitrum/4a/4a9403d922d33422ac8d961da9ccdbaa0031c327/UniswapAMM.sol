// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.16;
pragma experimental ABIEncoderV2;

// ==========================================================
// ====================== UniswapAMM ========================
// ==========================================================

// Primary Author(s)
// MAXOS Team: https://maxos.finance/

import "./ISweep.sol";
import "./Math.sol";
import "./SafeMath.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./TransferHelper.sol";
import "./Owned.sol";
import "./ISwapRouter.sol";

contract UniswapAMM is Owned {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;

    // Core
    ISweep private SWEEP;
    ERC20 private giveback_collateral;

    address public giveback_collateral_address;

    // Uniswap v3
    ISwapRouter public univ3_router;

    constructor(
        address _creator_address,
        address _sweep_contract_address,
        address _giveback_collateral_address,
        address _uniswap_router_address
    ) Owned(_creator_address) {
        SWEEP = ISweep(_sweep_contract_address);
        giveback_collateral_address = _giveback_collateral_address;
        giveback_collateral = ERC20(_giveback_collateral_address);
        univ3_router = ISwapRouter(_uniswap_router_address); //0xE592427A0AEce92De3Edee1F18E0157C05861564
    }

    event Bought(uint256 usdx_amount);
    event Sold(uint256 sweep_amount);

    /* ========== VIEWS ========== */

    function dollarBalances() public view returns (uint256 sweep_val_e18, uint256 collat_val_e18) {
        uint256 sweep_decimals = SWEEP.decimals();
        sweep_val_e18 = SWEEP.balanceOf(address(this)).div(sweep_decimals);

        uint256 collateral_decimals = giveback_collateral.decimals();
        collat_val_e18 = giveback_collateral.balanceOf(address(this)).div(collateral_decimals);
    }

    /* ========== Actions ========== */

    /**
    * @notice Buy Sweep
    * @param _collateral_address Token Address to use for buying sweep.
    * @param _collateral_amount Token Amount.
    * @dev Increases the sweep balance and decrease usdx balance.
    */
    function buySweep(address _collateral_address, uint256 _collateral_amount) public returns (uint256 sweep_amount) {
        uint256 sweep_price = SWEEP.amm_price();
        sweep_amount = swapExactInput(address(_collateral_address), address(SWEEP), _collateral_amount);
        SWEEP.refreshTargetPrice(sweep_price);

        emit Bought(sweep_amount);
    }

    /**
    * @notice Sell Sweep
    * @param _collateral_address Token Address to return after selling sweep.
    * @param _sweep_amount Sweep Amount.
    * @dev Decreases the sweep balance and increase usdx balance
    */
    function sellSweep(address _collateral_address, uint256 _sweep_amount) public returns (uint256 collateral_amount) {
        uint256 sweep_price = SWEEP.amm_price();
        collateral_amount = swapExactInput(address(SWEEP), address(_collateral_address), _sweep_amount);
        SWEEP.refreshTargetPrice(sweep_price);

        emit Sold(_sweep_amount);
    }

    /**
    * @notice Swap tokenA into tokenB using univ3_router.ExactInputSingle()
    * @param _tokenA Address to in
    * @param _tokenB Address to out
    * @param _amountIn Amount of _tokenA
    */
    function swapExactInput(address _tokenA, address _tokenB, uint256 _amountIn) public returns (uint256 amountOut) {
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
            amountOutMinimum: 0,
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

    /**
    * @notice setCollateral
    * @param _giveback_collateral_address.
    */
    function setCollateral(address _giveback_collateral_address) external onlyOwner {
        giveback_collateral_address = _giveback_collateral_address;
        giveback_collateral = ERC20(_giveback_collateral_address);
    }
}

