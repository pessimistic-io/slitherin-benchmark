// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { VaultGenesisStorageV1 } from "./VaultGenesisStorageV1.sol";
import { IVaultGenesis } from "./IVaultGenesis.sol";
import { ERC20Upgradeable } from "./ERC20Upgradeable.sol";
import { PausableUpgradeable } from "./PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { Initializable } from "./Initializable.sol";
import { SafeMathUpgradeable } from "./SafeMathUpgradeable.sol";
import { MathUpgradeable } from "./MathUpgradeable.sol";
import { IERC20 } from "./IERC20.sol";
import { IERC20Decimals } from "./IERC20Decimals.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { IOpenOceanExchange, IOpenOceanCaller } from "./IOpenOceanExchange.sol";

contract VaultGenesis is
    Initializable,
    ERC20Upgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    IVaultGenesis,
    VaultGenesisStorageV1
{
    using SafeERC20 for IERC20;
    using MathUpgradeable for uint256;
    using SafeMathUpgradeable for uint256;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        VaultSetting memory _vaultSetting,
        UnderlyingAssetStruct[] memory _underlyingAssets
    ) public initializer {
        __ERC20_init(_vaultSetting.name, _vaultSetting.symbol);
        __ReentrancyGuard_init();
        __Pausable_init();

        // pause first
        _pause();
        vaultStarted = false;

        denominator = IERC20(_vaultSetting.denominator);

        if (_vaultSetting.depositFee > 10_000) revert MAX_DEPOSIT_FEE_10000();
        depositFee = _vaultSetting.depositFee;

        if (_vaultSetting.withdrawFee > 10_000) revert MAX_WITHDRAW_FEE_10000();
        withdrawFee = _vaultSetting.withdrawFee;

        if (_vaultSetting.performanceFee > 10_000) revert MAX_PERFORMANCE_FEE_10000();
        performanceFee = _vaultSetting.performanceFee;

        if (_vaultSetting.protocolFee > 10_000) revert MAX_PROTOCOL_FEE_10000();
        protocolFee = _vaultSetting.protocolFee;

        // get the underlying asset's decimals
        denominatorDecimals = IERC20Decimals(address(denominator)).decimals();

        // manager and governor
        governor = msg.sender;
        manager = msg.sender;

        // fee recipient
        feeRecipient = msg.sender;

        // OpenOcean aggregation router
        aggregationRouter = 0x6352a56caadC4F1E25CD6c75970Fa768A3304e64;

        // prepare assets
        uint256 totalRatios = 0;
        for (uint256 i = 0; i < _underlyingAssets.length; ) {
            totalRatios += _underlyingAssets[i].ratio;
            _underlyingAssets[i].decimals = IERC20Decimals(_underlyingAssets[i].tokenAddress).decimals();
            underlyingAssets.push(_underlyingAssets[i]);
            unchecked {
                i++;
            }
        }

        // total ratio must be represent 100% / 10_000
        if (totalRatios != 10_000) revert TOTAL_RATIO_MUST_10000();
    }

    // =============================================================
    //                        Modifier
    // =============================================================

    modifier onlyGovernor() {
        if (msg.sender != governor) revert ONLY_GOVERNOR();
        _;
    }

    modifier onlyVaultManager() {
        if (msg.sender != manager) revert ONLY_MANAGER();
        _;
    }

    modifier onlyManagerOrGovernor() {
        if (msg.sender != manager && msg.sender != governor) revert ONLY_GOVERNOR_OR_MANAGER();
        _;
    }

    modifier onlyWhitelisted() {
        if (whitelistEnabled && whitelisted[msg.sender] == false) revert NOT_WHITELISTED();
        _;
    }

    // =============================================================
    //                        Start Vault
    // =============================================================
    /// @notice Start vault by burning an asset token ( 1000 wei )
    /// @dev This is to prevent against loss of precision and frontrunning the user deposits by sandwitch attack. Should be a non-trivial amount
    function startVault(bytes[] calldata data) public onlyManagerOrGovernor {
        if (vaultStarted == true) revert VAULT_HAS_STARTED();

        _unpause();

        // transfer denominator to this contract
        denominator.safeTransferFrom(msg.sender, address(this), 1000);

        // make share stuck in this contract
        deposit(1000, address(this), 900_000_000_000_000, data);

        vaultStarted = true;
    }

    // =============================================================
    //               Security & Manager Functions
    // =============================================================

    /// @notice pause the contract. Only manager role
    function pause() public onlyVaultManager {
        if (vaultStarted == false) revert VAULT_NOT_STARTED();
        _pause();
    }

    /// @notice unpause the contract. Only manager role
    function unpause() public onlyVaultManager {
        if (vaultStarted == false) revert VAULT_NOT_STARTED();
        _unpause();
    }

    function underlyingAssetsBalance() public view returns (uint256[] memory _underlyingAssets) {
        _underlyingAssets = new uint256[](underlyingAssets.length);

        for (uint256 i = 0; i < underlyingAssets.length; ) {
            _underlyingAssets[i] = IERC20(underlyingAssets[i].tokenAddress).balanceOf(address(this));
            unchecked {
                i++;
            }
        }

        return _underlyingAssets;
    }

    function deposit(
        uint256 amount,
        address receiver,
        uint256 minShares,
        bytes[] calldata data
    ) public nonReentrant whenNotPaused onlyWhitelisted returns (uint256 outShares) {
        if (data.length != underlyingAssets.length) revert INVALID_DATA();

        // transfer denominator to this contract
        denominator.safeTransferFrom(msg.sender, address(this), amount);

        // calculate fee
        uint256 amountDepositFee = (amount * 1e8 * depositFee) / 10_000 / 1e8; // precision 1e8

        // amount after deposit fee
        amount -= amountDepositFee;

        // transfer fee to fee recipient
        denominator.safeTransfer(feeRecipient, amountDepositFee);

        uint256 netAmount = 0;
        uint256 totalUnderlyingAssetsInDenominator = 0;

        for (uint256 i = 0; i < underlyingAssets.length; ) {
            uint256 swapAmount = amount.mulDiv(underlyingAssets[i].ratio, 10000);

            uint256 vaultUnderlyingAssetBalance = IERC20(underlyingAssets[i].tokenAddress).balanceOf(address(this));

            _swapOpenOcean(address(denominator), underlyingAssets[i].tokenAddress, swapAmount, data[i]);

            uint256 amountOut = IERC20(underlyingAssets[i].tokenAddress).balanceOf(address(this)) -
                vaultUnderlyingAssetBalance;

            if (amountOut == 0) revert ZERO_AMOUNT_OUT();

            uint256 underlyingAssetPrice = swapAmount.mulDiv(10 ** underlyingAssets[i].decimals, amountOut);

            totalUnderlyingAssetsInDenominator += vaultUnderlyingAssetBalance.mulDiv(
                underlyingAssetPrice,
                10 ** underlyingAssets[i].decimals
            );

            netAmount += underlyingAssetPrice.mulDiv(amountOut, 10 ** underlyingAssets[i].decimals);

            unchecked {
                i++;
            }
        }

        if (totalSupply() == 0) {
            outShares = netAmount.mul(10 ** decimals()).div(10 ** denominatorDecimals);
        } else {
            outShares = netAmount.mulDiv(totalSupply(), totalUnderlyingAssetsInDenominator);
        }

        // check output outShares < minShares
        if (outShares < minShares) revert INSUFFICIENT_OUTPUT_SHARES();

        _deposit(msg.sender, receiver, amount, outShares);

        return outShares;
    }

    // calculate swap Amounts for swap
    function calculateSwapAmountsForDeposit(
        uint256 amount,
        bool calculateFee
    ) public view returns (uint256[] memory swapAmounts) {
        // calculate fee
        uint256 amountDepositFee = 0;

        if (calculateFee) amountDepositFee = (amount * 1e8 * depositFee) / 10_000 / 1e8; // precision 1e18

        // net amount
        amount -= amountDepositFee;

        swapAmounts = new uint256[](underlyingAssets.length);
        for (uint256 i = 0; i < underlyingAssets.length; ) {
            uint256 swapAmount = amount.mulDiv(underlyingAssets[i].ratio, 10000);
            swapAmounts[i] = swapAmount;
            unchecked {
                i++;
            }
        }
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal {
        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

    function withdraw(
        uint256 shares,
        address receiver,
        address owner,
        uint256 minAmount,
        bytes[] calldata data
    ) external nonReentrant whenNotPaused onlyWhitelisted returns (uint256) {
        if (shares > balanceOf(owner) || balanceOf(owner) == 0) revert NOT_ENOUGH_SHARES();
        if (data.length != underlyingAssets.length) revert INVALID_DATA();

        uint256 netAmount = 0;

        uint256[] memory swapAmounts = calculateSwapAmountsForWithdraw(shares);

        for (uint256 i = 0; i < underlyingAssets.length; ) {
            uint256 vaultDenominatorBalance = IERC20(denominator).balanceOf(address(this));
            _swapOpenOcean(underlyingAssets[i].tokenAddress, address(denominator), swapAmounts[i], data[i]);
            netAmount += IERC20(denominator).balanceOf(address(this)) - vaultDenominatorBalance;
            unchecked {
                i++;
            }
        }

        // calculate fee
        uint256 amountWithdrawFee = (netAmount * 1e18 * withdrawFee) / 10_000 / 1e18; // precision 1e18
        denominator.safeTransfer(feeRecipient, amountWithdrawFee);

        netAmount -= amountWithdrawFee;

        if (netAmount < minAmount) revert INSUFFICIENT_OUTPUT_AMOUNT();

        // burn share and transfer the underlying asset
        _withdraw(msg.sender, receiver, owner, netAmount, shares);

        return netAmount;
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares) internal {
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        _burn(owner, shares);
        denominator.safeTransfer(receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    // calculate swap Amounts for swap
    function calculateSwapAmountsForWithdraw(uint256 shares) public view returns (uint256[] memory swapAmounts) {
        swapAmounts = new uint256[](underlyingAssets.length);
        uint256 shareProportion = shares.mulDiv(1e18, totalSupply());
        for (uint256 i = 0; i < underlyingAssets.length; ) {
            uint256 vaultUnderlyingAssetBalance = IERC20(underlyingAssets[i].tokenAddress).balanceOf(address(this));
            uint256 swapAmount = vaultUnderlyingAssetBalance.mulDiv(shareProportion, 1e18); //precision 1e18
            swapAmounts[i] = swapAmount;
            unchecked {
                i++;
            }
        }
    }

    // =============================================================
    //                     Manager Functions
    // =============================================================

    function transferGovernor(address newGovernor) public virtual onlyGovernor {
        if (newGovernor == address(0)) revert ZERO_ADDRESS();
        address oldGovernor = governor;
        governor = newGovernor;
        emit GovernorTransferred(oldGovernor, newGovernor);
    }

    function setVaultManager(address newVaultManager) external onlyGovernor {
        address oldVaultManager = manager;
        manager = newVaultManager;

        emit SetVaultManager(oldVaultManager, newVaultManager);
    }

    // =============================================================
    //                       Setting
    // =============================================================

    function setFeeRecipient(address _feeRecipient) public onlyGovernor {
        feeRecipient = _feeRecipient;
        emit FeeRecipientChanged(_feeRecipient);
    }

    function setDepositFee(uint256 _depositFee) public onlyManagerOrGovernor {
        if (_depositFee > 10_000) revert MAX_DEPOSIT_FEE_10000();
        depositFee = _depositFee;
        emit DepositFeeChanged(_depositFee);
    }

    function setWithdrawFee(uint256 _withdrawFee) public onlyManagerOrGovernor {
        if (_withdrawFee > 10_000) revert MAX_WITHDRAW_FEE_10000();
        withdrawFee = _withdrawFee;
        emit WithdrawFeeChanged(_withdrawFee);
    }

    function setPerformanceFee(uint256 _performanceFee) public onlyManagerOrGovernor {
        if (_performanceFee > 10_000) revert MAX_PERFORMANCE_FEE_10000();
        performanceFee = _performanceFee;
        emit PerformanceFeeChanged(_performanceFee);
    }

    function setProtocolFee(uint256 _protocolFee) public onlyGovernor {
        if (_protocolFee > 10_000) revert MAX_PROTOCOL_FEE_10000();
        protocolFee = _protocolFee;
        emit ProtocolFeeChanged(_protocolFee);
    }

    // =============================================================
    //                     Swap Function
    // =============================================================

    function _swapOpenOcean(address tokenIn, address tokenOut, uint256 amount, bytes calldata data) internal {
        IERC20(tokenIn).approve(address(aggregationRouter), amount);

        bytes4 method = _getMethod(data);

        // swap
        if (
            method ==
            bytes4(
                keccak256(
                    'swap(address,(address,address,address,address,uint256,uint256,uint256,uint256,address,bytes),(uint256,uint256,uint256,bytes)[])'
                )
            )
        ) {
            (, IOpenOceanExchange.SwapDescription memory desc, ) = abi.decode(
                data[4:],
                (IOpenOceanCaller, IOpenOceanExchange.SwapDescription, IOpenOceanCaller.CallDescription[])
            );

            if (tokenIn != address(desc.srcToken)) revert WRONG_TOKEN_IN();
            if (tokenOut != address(desc.dstToken)) revert WRONG_TOKEN_OUT();
            if (amount != desc.amount) revert WRONG_AMOUNT();
            if (address(this) != desc.dstReceiver) revert WRONG_DST();

            _callOpenOcean(data);
        }
        // uniswapV3SwapTo
        else if (method == bytes4(keccak256('uniswapV3SwapTo(address,uint256,uint256,uint256[])'))) {
            (address recipient, uint256 swapAmount, , ) = abi.decode(data[4:], (address, uint256, uint256, uint256[]));
            if (address(this) != recipient) revert WRONG_DST();
            if (amount != swapAmount) revert WRONG_AMOUNT();

            _callOpenOcean(data);
        }
        // callUniswapTo
        else if (method == bytes4(keccak256('callUniswapTo(address,uint256,uint256,bytes32[],address)'))) {
            (address srcToken, uint256 swapAmount, , , address recipient) = abi.decode(
                data[4:],
                (address, uint256, uint256, bytes32[], address)
            );
            if (tokenIn != srcToken) revert WRONG_TOKEN_IN();
            if (amount != swapAmount) revert WRONG_AMOUNT();
            if (address(this) != recipient) revert WRONG_DST();

            _callOpenOcean(data);
        } else {
            revert SWAP_METHOD_NOT_IDENTIFIED();
        }
    }

    function _getMethod(bytes memory data) internal pure returns (bytes4 method) {
        assembly {
            method := mload(add(data, add(32, 0)))
        }
    }

    function _callOpenOcean(bytes memory data) internal {
        (bool success, bytes memory result) = address(aggregationRouter).call(data);
        if (!success) {
            if (result.length < 68) revert SWAP_ERROR();
            assembly {
                result := add(result, 0x04)
            }
            revert(abi.decode(result, (string)));
        }
    }

    // =============================================================
    //                     Whitelist Setting
    // =============================================================

    function addWhitelist(address[] memory _whitelist) public onlyManagerOrGovernor {
        for (uint256 i = 0; i < _whitelist.length; ) {
            whitelisted[_whitelist[i]] = true;
            unchecked {
                i++;
            }
        }
        emit AddWhitelisted(_whitelist);
    }

    function removeWhitelist(address[] memory _whitelist) public onlyManagerOrGovernor {
        for (uint256 i = 0; i < _whitelist.length; ) {
            whitelisted[_whitelist[i]] = false;
            unchecked {
                i++;
            }
        }
        emit RemoveWhitelisted(_whitelist);
    }

    function enableWhitelist(bool status) public onlyManagerOrGovernor {
        whitelistEnabled = status;
    }

    function isWhitelisted(address user) public view returns (bool) {
        return whitelisted[user];
    }
}

