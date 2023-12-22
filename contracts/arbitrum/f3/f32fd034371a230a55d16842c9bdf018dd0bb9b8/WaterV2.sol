// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./OwnableUpgradeable.sol";
import "./ERC4626.sol";
import "./ERC4626Upgradeable.sol";
import "./MathUpgradeable.sol";

import "./ILeverageVault.sol";

contract WaterV2 is ERC4626Upgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using MathUpgradeable for uint256;

    address public USDC; // USDC
    address public sakeVault; // sake Vault address
    address public feeReceiver;
    uint256 public withdrawalFees;

    uint256 public constant DENOMINATOR = 10000;
    uint256 public WATER_DEFAULT_PRICE;
    uint256 private totalUSDC;
    uint256 public totalDebt;

    mapping(address => uint256) public userTimelock;
    uint256 public lockTime;
    uint256[50] private __gaps;

    modifier onlySakeVault() {
        require(msg.sender == sakeVault, "Not sake vault");
        _;
    }

    modifier zeroAddress(address addr) {
        require(addr != address(0), "ZERO_ADDRESS");
        _;
    }

    modifier checks(uint256 assetsOrShares) {
        require(assetsOrShares > 0, "VALUE_0");
        _;
    }

    event ProtocolFeeChanged(address newFeeReceiver, uint256 newwithdrawalFees);
    event LockTimeChanged(uint256 lockTime);

    event SakeVaultChanged(address newSakeVault);
    event Lend(address indexed user, uint256 amount);
    event RepayDebt(address indexed user, uint256 debtAmount, uint256 amountPaid);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _USDC) external initializer {
        require(_USDC != address(0), "ZERO_ADDRESS");
        USDC = _USDC;
        WATER_DEFAULT_PRICE = 1e18;
        withdrawalFees = 50;
        feeReceiver = msg.sender;
        lockTime = 48 hours;

        __Ownable_init();
        __ERC4626_init(IERC20Upgradeable(_USDC));
        __ERC20_init("Sake-WATER", "S-WATER");
    }

    /** ---------------- View functions --------------- */

    function balanceOfUSDC() public view returns (uint256) {
        return totalUSDC;
    }

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

    function changeSakeVault(address newAddr) external onlyOwner zeroAddress(newAddr) {
        sakeVault = newAddr;
        emit SakeVaultChanged(newAddr);
    }

    function changeProtocolFee(
        address _feeReceiver,
        uint256 _withdrawalFees
    ) external onlyOwner zeroAddress(_feeReceiver) checks(_withdrawalFees) {
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

    function lend(uint256 sake) external onlySakeVault returns (bool status) {
        require(totalUSDC > sake, "Not enough USDC to lend");

        totalDebt = totalDebt + sake;
        totalUSDC -= sake;

        require(ILeverageVault(sakeVault).getUtilizationRate() <= 8e17, "Leverage ratio too high");
        IERC20(USDC).safeTransfer(msg.sender, sake);
        emit Lend(msg.sender, sake);
        return true;
    }

    function repayDebt(uint256 _debtAmount, uint256 _amountPaid) external onlySakeVault returns (bool) {
        IERC20(USDC).safeTransferFrom(msg.sender, address(this), _amountPaid);
        totalDebt = totalDebt - _debtAmount;
        totalUSDC += _amountPaid;
        emit RepayDebt(msg.sender, _debtAmount, _amountPaid);
        return true;
    }

    function deposit(uint256 assets, address receiver) public override checks(assets) returns (uint256) {
        require(assets <= maxDeposit(receiver), "ERC4626: deposit more than max");

        uint256 actualAmount = assets;
        uint256 shares = previewDeposit(actualAmount);
        _deposit(_msgSender(), receiver, actualAmount, shares);
        totalUSDC += assets;
        userTimelock[receiver] = block.timestamp + lockTime;

        return shares;
    }

    /** @dev See {IERC4626-withdraw}. */
    function withdraw(
        uint256 _assets, // Native (USDC) token amount
        address _receiver,
        address _owner
    ) public override checks(_assets) returns (uint256) {
        require(_assets <= maxWithdraw(_owner), "ERC4626: withdraw more than max");
        require(balanceOfUSDC() > _assets, "Insufficient balance in vault");
        require(block.timestamp > userTimelock[_owner], "Still locked");

        uint256 shares = previewWithdraw(_assets);
        uint256 feeAmount = (_assets * withdrawalFees) / DENOMINATOR;
        IERC20(USDC).safeTransfer(feeReceiver, feeAmount);

        uint256 userAmount = _assets - feeAmount;

        _withdraw(_msgSender(), _receiver, _owner, userAmount, shares);
        totalUSDC -= _assets;
        return shares;
    }

    function mint(uint256 shares, address receiver) public virtual override returns (uint256) {
        revert("Not used");
    }

    function redeem(uint256 shares, address receiver, address owner) public virtual override returns (uint256) {
        revert("Not used");
    }
    
}

