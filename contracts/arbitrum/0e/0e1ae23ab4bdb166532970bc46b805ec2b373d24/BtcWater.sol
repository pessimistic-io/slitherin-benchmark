// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./OwnableUpgradeable.sol";
import "./ERC4626.sol";
import "./ERC4626Upgradeable.sol";
import "./MathUpgradeable.sol";

import "./ILeverageVault.sol";

interface IHandler {
    function getLatestData(address _token, bool _inDecimal) external view returns (uint256);
}

contract BtcWater is ERC4626Upgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using MathUpgradeable for uint256;

    address public WBTC;
    address public feeReceiver;
    uint256 public withdrawalFees;

    uint256 public constant DENOMINATOR = 10000;
    uint256 public WATER_DEFAULT_PRICE;
    uint256 private totalAsset;
    uint256 public totalDebt;
    uint256 public utilRate;

    mapping(address => uint256) public userTimelock;
    mapping(address => bool) public allowedToGift;
    mapping(address => bool) public allowedVaults;
    uint256 public lockTime;
    uint256[50] private __gaps;
    address vodkaHandler;

    modifier onlyAllowedVaults() {
        require(allowedVaults[msg.sender], "Not an allowed vault");
        _;
    }

    modifier onlyBTCGifter() {
        require(allowedToGift[msg.sender], "Not allowed to increment BTC");
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

    modifier stillLocked() {
        require(block.timestamp > userTimelock[msg.sender], "Still locked");
        _;
    }

    event ProtocolFeeChanged(address newFeeReceiver, uint256 newwithdrawalFees);
    event LockTimeChanged(uint256 lockTime);
    event Lend(address indexed user, uint256 amount);
    event RepayDebt(address indexed user, uint256 debtAmount, uint256 amountPaid);
    event BTCGifterAllowed(address indexed gifter, bool status);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _WBTC) external initializer {
        require(_WBTC != address(0), "ZERO_ADDRESS");
        WBTC = _WBTC;
        WATER_DEFAULT_PRICE = 1e18;
        feeReceiver = msg.sender;
        lockTime = 0;
        allowedToGift[msg.sender] = true;

        __Ownable_init();
        __ERC4626_init(IERC20Upgradeable(_WBTC));
        __ERC20_init("BTC-WATER", "BTC-WATER");
    }

    /** ---------------- View functions --------------- */

    function balanceOfAsset() public view returns (uint256) {
        return totalAsset;
    }

    function totalAssetInPrice() external view returns(uint256) {
        // price is outputed in pow 10^8
        uint256 getPrice = IHandler(vodkaHandler).getLatestData(WBTC, false);
        return totalAssets() * getPrice / 1e18;
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
        return totalAsset + totalDebt;
    }

    function getUtilizationRate() public view returns (uint256) {        
        return totalDebt == 0 ? 0 : totalDebt.mulDiv(1e18, balanceOfAsset() + totalDebt);
    }

    /** ----------- Change onlyOwner functions ------------- */

    function setVodkaHandler(address _vodkaHandler) external onlyOwner {
        vodkaHandler = _vodkaHandler;
    }

    function setAllowedVault(address _vault, bool _status) external onlyOwner zeroAddress(_vault) {
        allowedVaults[_vault] = _status;
    }

    function setUtilRate(uint256 _utilRate) public onlyOwner {
        require(_utilRate <= 1e18, "Invalid utilization rate");
        utilRate = _utilRate;
    }

    function allowBTCGifter(address _gifter, bool _status) external onlyOwner zeroAddress(_gifter) {
        allowedToGift[_gifter] = _status;
        emit BTCGifterAllowed(_gifter, _status);
    }

    function setProtocolFee(
        address _feeReceiver,
        uint256 _withdrawalFees
    ) external onlyOwner zeroAddress(_feeReceiver) noZeroValues(_withdrawalFees) {
        require(_withdrawalFees <= DENOMINATOR, "Invalid withdrawal fees");
        withdrawalFees = _withdrawalFees;
        feeReceiver = _feeReceiver;
        emit ProtocolFeeChanged(_feeReceiver, _withdrawalFees);
    }

    function setLockTime(uint256 _lockTime) public onlyOwner {
        require(_lockTime > 1 days, "Invalid lock time");
        lockTime = _lockTime;
        emit LockTimeChanged(_lockTime);
    }

    /**
     * @notice Allow the VodkaV2 Vault to lend a certain amount of BTC to the protocol.
     * @dev The function allows the VodkaV2 Vault to lend a certain amount of BTC to the protocol. It updates the total debt and total BTC balances accordingly.
     * @param _borrowed The amount of BTC to lend.
     * @return status A boolean indicating the success of the lending operation.
     */
    function lend(uint256 _borrowed, address _receiver) external onlyAllowedVaults returns (bool status) {
        uint256 am = _borrowed;
        require(totalAsset > am, "Not enough BTC to lend");

        totalDebt += _borrowed;
        totalAsset -= _borrowed;

        require(getUtilizationRate() <= utilRate, "Leverage ratio too high");
        IERC20(WBTC).safeTransfer(_receiver, am);

        emit Lend(_receiver, am);
        return true;
    }

    /**
     * @notice Allows the VodkaV2 Vault to repay debt to the protocol.
     * @dev The function allows the VodkaV2 Vault to repay a certain amount of debt to the protocol. It updates the total debt and total BTC balances accordingly.
     * @param _debtAmount The amount of debt to repay.
     * @param _amountPaid The amount of BTC paid to repay the debt.
     * @return A boolean indicating the success of the debt repayment operation.
     */
    function repayDebt(uint256 _debtAmount, uint256 _amountPaid) external onlyAllowedVaults returns (bool) {
        IERC20(WBTC).safeTransferFrom(msg.sender, address(this), _amountPaid);
        totalDebt = totalDebt - _debtAmount;
        totalAsset += _amountPaid;

        emit RepayDebt(msg.sender, _debtAmount, _amountPaid);
        return true;
    }

    /**
     * @notice Deposit assets into the contract for a receiver and receive corresponding shares.
     * @dev The function allows a user to deposit a certain amount of assets into the contract and receive the corresponding shares in return.
     *      It noZeroValues if the deposited assets do not exceed the maximum allowed deposit for the receiver.
     *      It then calculates the amount of shares to be issued to the user and calls the internal `_deposit` function to perform the actual deposit.
     *      It updates the total BTC balance and sets a timelock for the receiver.
     * @param _assets The amount of assets to deposit.
     * @param _receiver The address of the receiver who will receive the corresponding shares.
     * @return The amount of shares issued to the user.
     */
    function deposit(uint256 _assets, address _receiver) public override noZeroValues(_assets) returns (uint256) {
        IERC20(WBTC).transferFrom(msg.sender, address(this), _assets);
        uint256 shares = previewDeposit(_assets);

        _deposit(_msgSender(), msg.sender, _assets, shares);

        return shares;
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 _shares) internal override noZeroValues(assets) {
        require(assets <= maxDeposit(msg.sender), "ERC4626: deposit more than max");
        uint256 shares;
        if (totalSupply() == 0) {
            require(assets > 1000, "Not Enough Shares for first mint");
            // WBTC decimal is known to be 8
            uint256 SCALE = 10 ** decimals() / 10 ** 8;
            shares = (assets - 1000) * SCALE;
            _mint(address(this), 1000 * SCALE);
        } else {
            shares = _shares;
        }
        _mint(receiver, shares);

        totalAsset += assets;
        userTimelock[msg.sender] = block.timestamp + lockTime;
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @notice Withdraw assets from the contract for a receiver and return the corresponding shares.
     * @dev The function allows a user to withdraw a certain amount of assets from the contract and returns the corresponding shares.
     *      It noZeroValues if the withdrawn assets do not exceed the maximum allowed withdrawal for the owner.
     *      It also noZeroValues if there are sufficient assets in the vault to cover the withdrawal and if the user's withdrawal is not timelocked.
     *      It calculates the amount of shares to be returned to the user and calculates the withdrawal fee. It then transfers the fee amount to the fee receiver.
     *      The function then performs the actual withdrawal by calling the internal `_withdraw` function. It updates the total BTC balance after the withdrawal and returns the amount of shares returned to the user.
     * @param _assets The amount of assets (BTC) to withdraw.
     * @param _receiver The address of the receiver who will receive the corresponding shares.
     * @param _owner The address of the owner who is making the withdrawal.
     * @return The amount of shares returned to the user.
     */
    function withdraw(
        uint256 _assets, // Native (WBTC) token amount
        address _receiver,
        address _owner
    ) public override noZeroValues(_assets) stillLocked returns (uint256) {
        require(_assets <= maxWithdraw(msg.sender), "ERC4626: withdraw more than max");
        require(balanceOfAsset() >= _assets, "Insufficient balance in vault");

        uint256 shares = previewWithdraw(_assets);
        uint256 feeAmount = (_assets * withdrawalFees) / DENOMINATOR;

        uint256 userAmount = _assets - feeAmount;

        IERC20(WBTC).safeTransfer(feeReceiver, feeAmount);

        _withdraw(_msgSender(), msg.sender, msg.sender, userAmount, shares);
        totalAsset -= _assets;

        return shares;
    }

    function mint(uint256 shares, address receiver) public virtual override returns (uint256) {
        revert("Not used");
    }

    function redeem(uint256 shares, address receiver, address owner) public virtual override returns (uint256) {
        revert("Not used");
    }

    //function that only allows a whitelisted address to call to increase totalBTC
    function increaseTotalBTC(uint256 _amount) external onlyBTCGifter {
        IERC20(WBTC).safeTransferFrom(msg.sender, address(this), _amount);
        totalAsset += _amount;
    }

    receive() external payable {}
}

