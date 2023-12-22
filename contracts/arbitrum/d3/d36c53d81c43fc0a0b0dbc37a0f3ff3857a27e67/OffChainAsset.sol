// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.16;
pragma experimental ABIEncoderV2;

// ====================================================================
// ====================== OffChainAsset.sol ========================
// ====================================================================

/**
 * @title Off Chain Asset
 * @author MAXOS Team - https://maxos.finance/
 * @dev Representation of an off-chain investment
 */
import "./IStabilizer.sol";
import "./Owned.sol";
import "./IERC20Metadata.sol";
import "./TransferHelper.sol";

contract OffChainAsset is Owned {
    IERC20Metadata public usdx;

    // Variables
    bool public redeem_mode;
    uint256 public redeem_amount;
    uint256 public redeem_time;
    uint256 public current_value;
    uint256 public valuation_time;
    address public stabilizer;
    address public wallet;

    // Constants
    uint256 private constant DAY_TIMESTAMP = 24 * 60 * 60;

    // Events
    event Deposit(uint256 usdx_amount, uint256 sweep_amount);
    event Withdraw(uint256 amount);
    event Payback(address token, uint256 amount);

    // Errors
    error OnlyStabilizer();
    error OnlyBorrower();
    error SettingDisabled();
    error InvalidToken();
    error NotEnoughAmount();

    constructor(
        address _wallet,
        address _stabilizer,
        address _sweep_address,
        address _usdx_address
    ) Owned(_sweep_address) {
        wallet = _wallet;
        stabilizer = _stabilizer;
        usdx = IERC20Metadata(_usdx_address);
        redeem_mode = false;
    }

    modifier onlyStabilizer() {
        if (msg.sender != stabilizer) revert OnlyStabilizer();
        _;
    }

    modifier onlyBorrower() {
        if (msg.sender != IStabilizer(stabilizer).borrower())
            revert OnlyBorrower();
        _;
    }

    modifier onlySettingEnabled() {
        if (!IStabilizer(stabilizer).settings_enabled())
            revert SettingDisabled();
        _;
    }

    /**
     * @notice Current Value of investment.
     */
    function currentValue() external view returns (uint256) {
        return current_value;
    }

    /**
     * @notice Update wallet to send the investment to.
     * @param _wallet New wallet address.
     */
    function setWallet(address _wallet)
        external
        onlyBorrower
        onlySettingEnabled
    {
        wallet = _wallet;
    }

    /**
     * @notice Deposit stable coins into Off Chain asset.
     * @param usdx_amount USDX Amount of asset to be deposited.
     * @param sweep_amount Sweep Amount of asset to be deposited.
     * @dev tracks the time when current_value was updated.
     */
    function deposit(uint256 usdx_amount, uint256 sweep_amount)
        external
        onlyStabilizer
    {
        TransferHelper.safeTransferFrom(
            address(usdx),
            stabilizer,
            wallet,
            usdx_amount
        );
        TransferHelper.safeTransferFrom(
            address(SWEEP),
            stabilizer,
            wallet,
            sweep_amount
        );

        uint256 sweep_in_usdx = SWEEP.convertToUSDX(sweep_amount);
        current_value += usdx_amount;
        current_value += sweep_in_usdx;
        valuation_time = block.timestamp;

        emit Deposit(usdx_amount, sweep_amount);
    }

    /**
     * @notice Payback stable coins to Stabilizer
     * @param token token address to payback. USDX, SWEEP ...
     * @param amount The amount of usdx to payback.
     */
    function payback(address token, uint256 amount) external {
        if (token != address(SWEEP) && token != address(usdx))
            revert InvalidToken();
        if (token == address(SWEEP)) {
            amount = SWEEP.convertToUSDX(amount);
        }
        if (redeem_amount > amount) revert NotEnoughAmount();

        TransferHelper.safeTransferFrom(
            address(token),
            msg.sender,
            stabilizer,
            amount
        );

        current_value -= amount;
        redeem_mode = false;
        redeem_amount = 0;

        emit Payback(token, amount);
    }

    /**
     * @notice Withdraw usdx tokens from the asset.
     * @param amount The amount to withdraw.
     * @dev tracks the time when current_value was updated.
     */
    function withdraw(uint256 amount) external onlyStabilizer {
        redeem_amount = amount;
        redeem_mode = true;
        redeem_time = block.timestamp;

        emit Withdraw(amount);
    }

    /**
     * @notice Update Value of investment.
     * @param _value New value of investment.
     * @dev tracks the time when current_value was updated.
     */
    function updateValue(uint256 _value) external onlyCollateralAgent {
        current_value = _value;
        valuation_time = block.timestamp;
    }

    /**
     * @notice Withdraw Rewards.
     * @dev this function was added to generate compatibility with On Chain investment.
     */
    function withdrawRewards(address _owner) external {}
    
    function liquidate(address, uint256) external {}
}

