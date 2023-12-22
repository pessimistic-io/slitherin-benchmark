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
import "./ISweep.sol";
import "./Owned.sol";
import "./IERC20Metadata.sol";
import "./TransferHelper.sol";

contract OffChainAsset is Owned {
    IERC20Metadata public usdx;
    ISweep public sweep;

    // Variables
    bool public redeem_mode;
    uint256 public redeem_amount;
    uint256 public redeem_time;
    uint8 public delay; // Days 
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

    constructor(
        address _owner,
        address _wallet,
        address _stabilizer,
        address _sweep_address,
        address _usdx_address
    ) Owned(_owner) {
        wallet = _wallet;
        stabilizer = _stabilizer;
        sweep = ISweep(_sweep_address);
        usdx = IERC20Metadata(_usdx_address);
        redeem_mode = false;
    }

    modifier onlyStabilizer() {
        require(msg.sender == stabilizer, "only stabilizer");
        _;
    }

    /**
     * @notice Current Value of investment.
     */
    function currentValue() external view returns (uint256) {
        return current_value;
    }

    /**
     * @notice isDefaulted
     * Check whether the redeem is executed.
     * @return bool True: is defaulted, False: not defaulted.
     */
    function isDefaulted() public view returns (bool) {
        bool isPassed = redeem_time + (delay * DAY_TIMESTAMP) < block.timestamp;

        return redeem_mode && isPassed;
    }

    /**
     * @notice Update wallet to send the investment to.
     * @param _wallet New wallet address.
     */
    function setWallet(address _wallet) public onlyOwner {
        wallet = _wallet;
    }

    /**
     * @notice Set Delay
     * @param _delay Days for delay.
     */
    function setDelay(uint8 _delay) external onlyOwner {
        delay = _delay;
    }

    /**
     * @notice Deposit stable coins into Off Chain asset.
     * @param usdx_amount USDX Amount of asset to be deposited.
     * @param sweep_amount Sweep Amount of asset to be deposited.
     * @dev tracks the time when current_value was updated.
     */
    function deposit(uint256 usdx_amount, uint256 sweep_amount) public onlyStabilizer {
        TransferHelper.safeTransferFrom(
            address(usdx),
            stabilizer,
            wallet,
            usdx_amount
        );
        TransferHelper.safeTransferFrom(
            address(sweep),
            stabilizer,
            wallet,
            sweep_amount
        );

        uint256 sweep_in_usdx = SWEEPinUSDX(sweep_amount, sweep.target_price());
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
    function payback(address token, uint256 amount) public {
        require(token == address(sweep) || token == address(usdx), "Invalid Token");

        if(token == address(sweep)) {
            amount = SWEEPinUSDX(amount, sweep.target_price());
        }
        require(redeem_amount <= amount, "Not enough amount");

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
    function withdraw(uint256 amount) public onlyStabilizer {
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
    function updateValue(uint256 _value) public onlyOwner {
        current_value = _value;
        valuation_time = block.timestamp;
    }

    /**
     * @notice Reset the redeem mode.
     */
    function resetRedeem() public onlyOwner {
        redeem_amount = 0;
        redeem_mode = false;
    }

    /**
     * @notice SWEEP in USDX
     * Calculate the amount of USDX that are equivalent to the SWEEP input.
     * @param amount Amount of SWEEP.
     * @param price Price of Sweep in USDX. This value is obtained from the AMM.
     * @return amount of USDX.
     * @dev 1e6 = PRICE_PRECISION
     */
    function SWEEPinUSDX(uint256 amount, uint256 price)
        internal
        view
        returns (uint256)
    {
        return (amount * price * (10**usdx.decimals())) / (10**sweep.decimals() * 1e6);
    }

    /**
     * @notice Withdraw Rewards.
     * @dev this function was added to generate compatibility with On Chain investment.
     */
    function withdrawRewards(address _owner) public {}
}

