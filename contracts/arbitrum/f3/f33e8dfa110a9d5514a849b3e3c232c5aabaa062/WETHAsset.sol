// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.16;
pragma experimental ABIEncoderV2;

// ====================================================================
// ========================== WETHAsset.sol ===========================
// ====================================================================

/**
 * @title WETH Asset
 * @author MAXOS Team - https://maxos.finance/
 */
import "./IAMM.sol";
import "./IWETH.sol";
import "./Owned.sol";
import "./IERC20.sol";
import "./AggregatorV3Interface.sol";
import "./TransferHelper.sol";

contract WETHAsset is Owned {
    IWETH public WETH;
    IERC20 public usdx;
    IAMM public uniswap_amm;
    address public stabilizer;

    // oracle to fetch price WETH / USDC
    AggregatorV3Interface private immutable oracle;
    uint256 private PRICE_PRECISION = 1e6;

    // Events
    event Deposited(address collateral_address, uint256 amount);
    event Withdrawed(address collateral_address, uint256 amount);

    constructor(
        address _sweep_address,
        address _weth_address,
        address _usdx_address,
        address _uniswap_amm,
        address _stabilizer_address,
        address _chainlink_oracle
    ) Owned(_sweep_address) {
        WETH = IWETH(_weth_address);
        usdx = IERC20(_usdx_address);
        uniswap_amm = IAMM(_uniswap_amm);
        stabilizer = _stabilizer_address;
        oracle = AggregatorV3Interface(_chainlink_oracle);
    }

    modifier onlyStabilizer() {
        require(msg.sender == stabilizer, "only stabilizer");
        _;
    }

    // ACTIONS ===========================
    /**
     * @notice Current Value of investment.
     * @return usdx_amount Returns the value of the investment in the USD coin
     * @dev the price is obtained from Chainlink
     */
    function currentValue() external view returns (uint256) {
        uint256 weth_balance = WETH.balanceOf(address(this));
        (, int256 price, , , ) = oracle.latestRoundData();        
        
        uint256 usdx_amount = 
            (weth_balance * uint256(price) * PRICE_PRECISION) /
            (10**(WETH.decimals() + oracle.decimals()));
        
        return usdx_amount;
    }

    /**
     * @notice Function to deposit USDX from Stabilizer to Asset
     * @param amount USDX amount of asset to be deposited
     */
    function deposit(uint256 amount, uint256) external onlyStabilizer {
        address usdx_address = address(usdx);
        TransferHelper.safeTransferFrom(
            address(usdx),
            msg.sender,
            address(this),
            amount
        );
        
        TransferHelper.safeApprove(usdx_address, address(uniswap_amm), amount);
        uint256 weth_amount = uniswap_amm.swapExactInput(
            usdx_address,
            address(WETH),
            amount,
            0
        );

        emit Deposited(address(usdx), weth_amount);
    }

    /**
     * @notice Function to withdraw USDX from ASSET to Stabilizer
     * @param amount Amount of tokens to be withdrew
     */
    function withdraw(uint256 amount) external onlyStabilizer {
        uint256 weth_amount = amount;
        if(amount != type(uint256).max) {
            (, int256 price, , , ) = oracle.latestRoundData();
            weth_amount =
                (amount * (10**(WETH.decimals() + oracle.decimals()))) /
                (uint256(price) * PRICE_PRECISION);
        }
        
        uint256 weth_balance = WETH.balanceOf(address(this));
        
        if(weth_amount > weth_balance) weth_amount = weth_balance;
        
        address usdx_address = address(usdx);
        address weth_address = address(WETH);
        
        TransferHelper.safeApprove(weth_address, address(uniswap_amm), weth_amount);
        uint256 usdx_amount = uniswap_amm.swapExactInput(
            weth_address,
            usdx_address,
            weth_amount,
            0
        );

        TransferHelper.safeTransfer(usdx_address, stabilizer, usdx_amount);

        emit Withdrawed(usdx_address, usdx_amount);
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
        (, int256 price, , , ) = oracle.latestRoundData();
        uint256 weth_amount =
                (amount * (10**(WETH.decimals() + oracle.decimals()))) /
                (uint256(price) * PRICE_PRECISION);
        
        WETH.transfer(to, weth_amount);
    }

    /**
     * @notice compliance with the IAsset.sol
     */
    function withdrawRewards(address) external pure {}

    function updateValue(uint256) external pure {}
}

