// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.16;
pragma experimental ABIEncoderV2;

// ====================================================================
// ====================== AaveV3Asset.sol ==========================
// ====================================================================
// Intergrated with Aave V3

// Primary Author(s)
// MAXOS Team: https://maxos.finance/

import "./ISweep.sol";
import "./IAaveV3Pool.sol";
import "./Owned.sol";
import "./IERC20.sol";
import "./TransferHelper.sol";

contract AaveV3Asset is Owned {
    // Variables
    address public stabilizer;

    // Tokens
    IERC20 public USDX;
    IERC20 private aaveUSDX_Token;

    // Pools
    IPool private aaveV3_Pool;

    // Events
    event Deposit(address collateral_address, uint256 amount);
    event Withdraw(address collateral_address, uint256 amount);
    event WithdrawRewards(uint256 stkAave_amount, uint256 aave_amount);

    constructor(
        address _sweep_address,
        address _stabilizer_address,
        address _aaveV3_pool_address,
        address _usdx_address,
        address _aave_usdx_address
    ) Owned(_sweep_address) {
        stabilizer = _stabilizer_address;
        aaveV3_Pool = IPool(_aaveV3_pool_address);
        USDX = IERC20(_usdx_address); // USDC
        aaveUSDX_Token = IERC20(_aave_usdx_address); //aaveUSDC
    }

    /* ========== Modifies ========== */

    modifier onlyStabilizer() {
        require(msg.sender == stabilizer, "only stabilizer");
        _;
    }

    /* ========== Views ========== */

    /**
     * @notice Gets the current value in USDX of this OnChainAsset
     * @return the current usdx amount
     */
    function currentValue() public view returns (uint256) {
        // All numbers given are in USDX unless otherwise stated
        return aaveUSDX_Token.balanceOf(address(this));
    }

    /* ========== Actions ========== */

    /**
     * @notice Function to deposit USDX from Stabilizer to AMO
     * @param amount USDX Amount of asset to be deposited
     */
    function deposit(uint256 amount, uint256) public onlyStabilizer {
        require(amount > 0, "Over Zero");
        TransferHelper.safeTransferFrom(
            address(USDX),
            msg.sender,
            address(this),
            amount
        );
        TransferHelper.safeApprove(address(USDX), address(aaveV3_Pool), amount);
        aaveV3_Pool.supply(address(USDX), amount, address(this), 0);

        emit Deposit(address(USDX), amount);
    }

    /**
     * @notice Function to withdraw USDX from AMO to Stabilizer
     * @param amount Amount of asset to be withdrawed - E18
     */
    function withdraw(uint256 amount) public onlyStabilizer {
        if(currentValue() < amount) amount = type(uint256).max;
        aaveV3_Pool.withdraw(address(USDX), amount, msg.sender);

        emit Withdraw(address(USDX), amount);
    }

    /**
     * @notice Function to Recover Erc20 token to Stablizer
     * @param token token address to be recovered
     * @param amount token amount to be recovered
     */
    function recoverERC20(address token, uint256 amount)
        external
        onlyStabilizer
    {
        TransferHelper.safeTransfer(address(token), msg.sender, amount);
    }

    /**
     * @notice Liquidate
     * @param to address to receive the tokens
     * @param amount token amount to send
     */
    function liquidate(address to, uint256 amount)
        external
        onlyStabilizer
    {
        aaveUSDX_Token.transfer(to, amount);
    }

    /**
     * @notice compliance with the IAsset.sol
     */
    function withdrawRewards(address) external pure {}

    function updateValue(uint256) external pure {}
}

