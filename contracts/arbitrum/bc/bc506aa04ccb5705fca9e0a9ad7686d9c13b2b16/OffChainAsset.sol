// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.16;
pragma experimental ABIEncoderV2;

// ====================================================================
// ====================== OffChainAsset.sol ===========================
// ====================================================================

/**
 * @title Off Chain Asset
 * @author MAXOS Team - https://maxos.finance/
 * @dev Representation of an off-chain investment
 */
import "./ISweep.sol";
import "./Owned.sol";
import "./TransferHelper.sol";
import "./ERC20.sol";

contract OffChainAsset is Owned {
    bool public redeem_mode;
    uint256 public redeem_amount;

    uint256 public current_value;
    uint256 public valuation_time;
    address public stabilizer;
    address public wallet;
    string public link;

    ERC20 public usdx;
    ISweep public sweep;

    // Events 
    event Deposit(address token, uint256 amount);
    event Withdraw(uint256 amount);

    constructor(
        address _owner,
        address _wallet,
        address _stabilizer,
        string memory _link,
        address _sweep_address,
        address _usdx_address
    ) Owned(_owner) {
        wallet = _wallet;
        stabilizer = _stabilizer;
        link = _link;
        sweep = ISweep(_sweep_address);
        usdx = ERC20(_usdx_address);
        redeem_mode = false;
    }

    modifier onlyStabilizer() {
        require(msg.sender == stabilizer, "only stabilizer");
        _;
    }

    /**
     * @notice Deposit stable coins into Off Chain asset.
     * @param token token address to deposit. USDX, SWEEP ...
     * @param amount The amount of usdx to deposit in the asset.
     * @dev tracks the time when current_value was updated.
     */
    function deposit(address token, uint256 amount) public onlyStabilizer {
        require(wallet != address(0), "Invaild Address");
        
        TransferHelper.safeTransferFrom(
            address(token),
            stabilizer,
            wallet,
            amount
        );
        
        if(token == address(sweep)) {
            uint256 sweep_in_usdx = SWEEPinUSDX(amount, sweep.target_price());
            current_value += sweep_in_usdx;
        } else {
            current_value += amount;
        }
        valuation_time = block.timestamp;

        emit Deposit(token, amount);
    }

    /**
     * @notice Withdraw usdx tokens from the asset.
     * @param amount The amount to withdraw.
     * @dev tracks the time when current_value was updated.
     */
    function withdraw(uint256 amount) public onlyStabilizer {
        redeem_amount = amount;
        redeem_mode = true;

        emit Withdraw(amount);
    }

    /**
     * @notice Current Value of investment.
     */
    function currentValue() external view returns (uint256) {
        return current_value;
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
     * @notice Update wallet to send the investment to.
     * @param _wallet New wallet address.
     */
    function setWallet(address _wallet) public onlyOwner {
        wallet = _wallet;
    }

    /**
     * @notice Update Link
     * @param _link New link.
     */
    function setLink(string calldata _link) external onlyOwner {
        link = _link;
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

