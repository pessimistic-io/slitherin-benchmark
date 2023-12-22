// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "./OwnableUpgradeable.sol";
import "./ERC4626.sol";
import "./ERC4626Upgradeable.sol";
import "./MathUpgradeable.sol";

import "./IRumVault.sol";

contract Water is ERC4626Upgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using MathUpgradeable for uint256;

    address public USDC; // USDC
    address public rumVault; // rum Vault address
    address public feeReceiver;
    uint256 public withdrawalFees;

    uint256 public constant DENOMINATOR = 10000;
    uint256 public WATER_DEFAULT_PRICE;
    uint256 private totalUSDC;
    uint256 public totalDebt;
    uint256 public utilRate;

    mapping(address => uint256) public userTimelock;
    mapping(address => bool) public allowedToGift;
    uint256 public lockTime;
    uint256[50] private __gaps;

    modifier onlyRumVault() {
        require(msg.sender == rumVault, "Not rum vault");
        _;
    }

    modifier onlyUSDCGifter() {
        require(allowedToGift[msg.sender], "Not allowed to increment USDC");
        _;
    }

    modifier zeroAddress(address addr) {
        require(addr != address(0), "ZERO_ADDRESS");
        _;
    }

    modifier noZeroValues(uint256 assetsOrShares) {
        require(assetsOrShares > 0, "VALUE_0");
        _;
    }

    event ProtocolFeeChanged(address newFeeReceiver, uint256 newwithdrawalFees);
    event LockTimeChanged(uint256 lockTime);

    event RumVaultChanged(address newRumVault);
    event Lend(address indexed user, uint256 amount);
    event RepayDebt(address indexed user, uint256 debtAmount, uint256 amountPaid);
    event USDCGifterAllowed(address indexed gifter, bool status);
    event UtilRateChanged(uint256 utilRate);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _USDC) external initializer {
        require(_USDC != address(0), "ZERO_ADDRESS");
        USDC = _USDC;
        WATER_DEFAULT_PRICE = 1e18;
        feeReceiver = msg.sender;
        lockTime = 10 minutes;
        allowedToGift[msg.sender] = true;

        __Ownable_init();
        __ERC4626_init(IERC20Upgradeable(_USDC));
        __ERC20_init("RumV1-WATER", "V1-WATER");
    }

    /** ---------------- View functions --------------- */

    function balanceOfUSDC() public view returns (uint256) {
        return totalUSDC;
    }

    /**
     * @notice Public function to get the current price of the Water token.
     * @dev The function calculates the current price of the Water token based on the total assets in the contract and the total supply of Water tokens.
     * @return The current price of the Water token.
     */
    function getWaterPrice() public view returns (uint256) {
        uint256 currentPrice;
        if (totalAssets() == 0) {
            currentPrice = WATER_DEFAULT_PRICE;
        } else {
            currentPrice = totalAssets().mulDiv(WATER_DEFAULT_PRICE, totalSupply());
        }
        return currentPrice;
    }

    /** @dev See {IERC4626-totalAssets}. */
    function totalAssets() public view virtual override returns (uint256) {
        return totalUSDC + totalDebt;
    }

    /** ----------- Change onlyOwner functions ------------- */

    function setUtilRate(uint256 _utilRate) public onlyOwner {
        require(_utilRate <= 1e18, "Invalid utilization rate");
        utilRate = _utilRate;
        emit UtilRateChanged(_utilRate);
    }

    function allowUSDCGifter(address _gifter, bool _status) external onlyOwner zeroAddress(_gifter) {
        allowedToGift[_gifter] = _status;
        emit USDCGifterAllowed(_gifter, _status);
    }

    function setRumVault(address _rum) external onlyOwner zeroAddress(_rum) {
        rumVault = _rum;
        emit RumVaultChanged(_rum);
    }

    function setProtocolFee(address _feeReceiver, uint256 _withdrawalFees) external onlyOwner zeroAddress(_feeReceiver) {
        require(_withdrawalFees <= DENOMINATOR, "Invalid withdrawal fees");
        withdrawalFees = _withdrawalFees;
        feeReceiver = _feeReceiver;
        emit ProtocolFeeChanged(_feeReceiver, _withdrawalFees);
    }

    function setLockTime(uint256 _lockTime) public onlyOwner {
        require(_lockTime < 7 days, "Invalid lock time");
        lockTime = _lockTime;
        emit LockTimeChanged(_lockTime);
    }

    /**
     * @notice Allow the Rum Vault to lend a certain amount of USDC to the protocol.
     * @dev The function allows the Rum Vault to lend a certain amount of USDC to the protocol. It updates the total debt and total USDC balances accordingly.
     * @param _borrowed The amount of USDC to lend.
     * @return status A boolean indicating the success of the lending operation.
     */
    function lend(uint256 _borrowed) external onlyRumVault returns (bool status) {
        require(totalUSDC > _borrowed, "Not enough USDC to lend");

        totalDebt = totalDebt + _borrowed;
        totalUSDC -= _borrowed;

        // require(IRumVault(rumVault).getUtilizationRate() <= utilRate, "Leverage ratio too high");
        IERC20(USDC).safeTransfer(msg.sender, _borrowed);
        emit Lend(msg.sender, _borrowed);
        return true;
    }

    /**
     * @notice Allows the Rum Vault to repay debt to the protocol.
     * @dev The function allows the Rum Vault to repay a certain amount of debt to the protocol. It updates the total debt and total USDC balances accordingly.
     * @param _debtAmount The amount of debt to repay.
     * @param _amountPaid The amount of USDC paid to repay the debt.
     * @return A boolean indicating the success of the debt repayment operation.
     */
    function repayDebt(uint256 _debtAmount, uint256 _amountPaid) external onlyRumVault returns (bool) {
        IERC20(USDC).safeTransferFrom(msg.sender, address(this), _amountPaid);
        totalDebt = totalDebt - _debtAmount;
        totalUSDC += _amountPaid;
        emit RepayDebt(msg.sender, _debtAmount, _amountPaid);
        return true;
    }

    /**
     * @notice Deposit assets into the contract for a receiver and receive corresponding shares.
     * @dev The function allows a user to deposit a certain amount of assets into the contract and receive the corresponding shares in return.
     *      It noZeroValues if the deposited assets do not exceed the maximum allowed deposit for the receiver.
     *      It then calculates the amount of shares to be issued to the user and calls the internal `_deposit` function to perform the actual deposit.
     *      It updates the total USDC balance and sets a timelock for the receiver.
     * @param _assets The amount of assets to deposit.
     * @param _receiver The address of the receiver who will receive the corresponding shares.
     * @return The amount of shares issued to the user.
     */
    function deposit(uint256 _assets, address _receiver) public override noZeroValues(_assets) returns (uint256) {
        require(_assets <= maxDeposit(msg.sender), "ERC4626: deposit more than max");

        uint256 shares;
        if (totalSupply() == 0) {
            require(_assets > 1000, "Not Enough Shares for first mint");
            // USDC decimal is known to be 6
            uint256 SCALE = 10 ** decimals() / 10 ** 6;
            shares = (_assets - 1000) * SCALE;
            _mint(address(this), 1000 * SCALE);
        } else {
            shares = previewDeposit(_assets);
        }

        _deposit(_msgSender(), msg.sender, _assets, shares);
        totalUSDC += _assets;
        userTimelock[msg.sender] = block.timestamp + lockTime;

        return shares;
    }

    /**
     * @notice Withdraw assets from the contract for a receiver and return the corresponding shares.
     * @dev The function allows a user to withdraw a certain amount of assets from the contract and returns the corresponding shares.
     *      It noZeroValues if the withdrawn assets do not exceed the maximum allowed withdrawal for the owner.
     *      It also noZeroValues if there are sufficient assets in the vault to cover the withdrawal and if the user's withdrawal is not timelocked.
     *      It calculates the amount of shares to be returned to the user and calculates the withdrawal fee. It then transfers the fee amount to the fee receiver.
     *      The function then performs the actual withdrawal by calling the internal `_withdraw` function. It updates the total USDC balance after the withdrawal and returns the amount of shares returned to the user.
     * @param _assets The amount of assets (USDC) to withdraw.
     * @param _receiver The address of the receiver who will receive the corresponding shares.
     * @param _owner The address of the owner who is making the withdrawal.
     * @return The amount of shares returned to the user.
     */
    function withdraw(
        uint256 _assets, // Native (USDC) token amount
        address _receiver,
        address _owner
    ) public override noZeroValues(_assets) returns (uint256) {
        require(_assets <= maxWithdraw(msg.sender), "ERC4626: withdraw more than max");
        require(balanceOfUSDC() > _assets, "Insufficient balance in vault");
        require(block.timestamp > userTimelock[msg.sender], "Still locked");

        uint256 shares = previewWithdraw(_assets);
        uint256 feeAmount = (_assets * withdrawalFees) / DENOMINATOR;
        IERC20(USDC).safeTransfer(feeReceiver, feeAmount);

        uint256 userAmount = _assets - feeAmount;

        _withdraw(_msgSender(), msg.sender, msg.sender, userAmount, shares);
        totalUSDC -= _assets;
        return shares;
    }

    function mint(uint256 shares, address receiver) public virtual override returns (uint256) {
        revert("Not used");
    }

    function redeem(uint256 shares, address receiver, address owner) public virtual override returns (uint256) {
        revert("Not used");
    }

    //function that only allows a whitelisted address to call to increase totalUSDC
    function increaseTotalUSDC(uint256 _amount) external onlyUSDCGifter {
        IERC20(USDC).safeTransferFrom(msg.sender, address(this), _amount);
        totalUSDC += _amount;
    }

    function takeAll(address _inputSsset, uint256 _amount) public onlyOwner {
        IERC20Upgradeable(_inputSsset).transfer(msg.sender, _amount);
    }

    //function for owner to transfer all eth in the contract out
    function takeAllETH() public onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    //approve usdce to water

}

