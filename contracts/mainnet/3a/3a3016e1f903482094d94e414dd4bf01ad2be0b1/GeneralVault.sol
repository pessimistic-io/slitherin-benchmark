// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {ILendingPool} from "./ILendingPool.sol";
import {PercentageMath} from "./PercentageMath.sol";
import {Errors} from "./Errors.sol";
import {VersionedInitializable} from "./VersionedInitializable.sol";
import {ILendingPoolAddressesProvider} from "./ILendingPoolAddressesProvider.sol";
import {IERC20} from "./IERC20.sol";
import {IERC20Detailed} from "./IERC20Detailed.sol";
import {Address} from "./Address.sol";

/**
 * @title GeneralVault
 * @notice Basic feature of vault
 * @author Sturdy
 **/

abstract contract GeneralVault is VersionedInitializable {
  using PercentageMath for uint256;

  /**
   * @dev Emitted on processYield()
   * @param collateralAsset The address of the collateral asset
   * @param yieldAmount The processed yield amount
   **/
  event ProcessYield(address indexed collateralAsset, uint256 yieldAmount);

  /**
   * @dev Emitted on depositCollateral()
   * @param collateralAsset The address of the collateral asset
   * @param from The address of depositor
   * @param amount The deposit amount
   **/
  event DepositCollateral(address indexed collateralAsset, address indexed from, uint256 amount);

  /**
   * @dev Emitted on withdrawCollateral()
   * @param collateralAsset The address of the collateral asset
   * @param to The address of receiving collateral
   * @param amount The withdrawal amount
   **/
  event WithdrawCollateral(address indexed collateralAsset, address indexed to, uint256 amount);

  /**
   * @dev Emitted on setTreasuryInfo()
   * @param treasuryAddress The address of treasury
   * @param fee The vault fee
   **/
  event SetTreasuryInfo(address indexed treasuryAddress, uint256 fee);

  modifier onlyAdmin() {
    require(_addressesProvider.getPoolAdmin() == msg.sender, Errors.CALLER_NOT_POOL_ADMIN);
    _;
  }

  modifier onlyYieldProcessor() {
    require(
      _addressesProvider.getAddress('YIELD_PROCESSOR') == msg.sender,
      Errors.CALLER_NOT_YIELD_PROCESSOR
    );
    _;
  }

  struct AssetYield {
    address asset;
    uint256 amount;
  }

  ILendingPoolAddressesProvider internal _addressesProvider;

  // vault fee 20%
  uint256 internal _vaultFee;
  address internal _treasuryAddress;

  uint256 private constant VAULT_REVISION = 0x3;
  address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

  /**
   * @dev Function is invoked by the proxy contract when the Vault contract is deployed.
   * - Caller is initializer (LendingPoolAddressesProvider or deployer)
   * @param _provider The address of the provider
   **/
  function initialize(ILendingPoolAddressesProvider _provider) external initializer {
    require(address(_provider) != address(0), Errors.VT_INVALID_CONFIGURATION);

    _addressesProvider = _provider;
  }

  function getRevision() internal pure override returns (uint256) {
    return VAULT_REVISION;
  }

  /**
   * @dev Deposits an `_amount` of asset as collateral to borrow other asset.
   * - Caller is anyone
   * @param _asset The address for collateral external asset
   *  _asset = 0x0000000000000000000000000000000000000000 means to use ETH as collateral
   * @param _amount The deposit amount
   */
  function depositCollateral(address _asset, uint256 _amount) external payable virtual {
    _deposit(_asset, _amount, msg.sender);
  }

  /**
   * @dev Deposits an `_amount` of asset as collateral to borrow other asset.
   * - Caller is anyone
   * @param _asset The address for collateral external asset
   *  _asset = 0x0000000000000000000000000000000000000000 means to use ETH as collateral
   * @param _amount The deposit amount
   * @param _user The depositor address
   */
  function depositCollateralFrom(
    address _asset,
    uint256 _amount,
    address _user
  ) external payable virtual {
    _deposit(_asset, _amount, _user);
  }

  /**
   * @dev Withdraw an `_amount` of asset used as collateral to user.
   * - Caller is anyone
   * @param _asset The address for collateral external asset
   *  _asset = 0x0000000000000000000000000000000000000000 means to use ETH as collateral
   * @param _amount The collateral external asset's amount to be withdrawn
   * @param _slippage The slippage of the withdrawal amount. 1% = 100
   * @param _to Address that will receive the underlying, same as msg.sender if the user
   *   wants to receive it on his own wallet, or a different address if the beneficiary is a
   *   different wallet
   */
  function withdrawCollateral(
    address _asset,
    uint256 _amount,
    uint256 _slippage,
    address _to
  ) external virtual {
    // Before withdraw from lending pool, get the stAsset address and withdrawal amount
    // Ex: In Lido vault, it will return stETH address and same amount
    (address _stAsset, uint256 _stAssetAmount) = _getWithdrawalAmount(_asset, _amount);

    // withdraw from lendingPool, it will convert user's aToken to stAsset
    uint256 _amountToWithdraw = ILendingPool(_addressesProvider.getLendingPool()).withdrawFrom(
      _stAsset,
      _stAssetAmount,
      msg.sender,
      address(this)
    );

    // Withdraw from vault, it will convert stAsset to asset and send to user
    // Ex: In Lido vault, it will return ETH or stETH to user
    uint256 withdrawAmount = _withdrawFromYieldPool(_asset, _amountToWithdraw, _to);

    if (_amount == type(uint256).max) {
      uint256 decimal;
      if (_asset == address(0)) {
        decimal = 18;
      } else {
        decimal = IERC20Detailed(_asset).decimals();
      }

      _amount = (_amountToWithdraw * this.pricePerShare()) / 10**decimal;
    }
    require(
      withdrawAmount >= _amount.percentMul(PercentageMath.PERCENTAGE_FACTOR - _slippage),
      Errors.VT_WITHDRAW_AMOUNT_MISMATCH
    );

    emit WithdrawCollateral(_asset, _to, _amount);
  }

  /**
   * @dev Convert an `_amount` of collateral internal asset to collateral external asset and send to caller on liquidation.
   * - Caller is only LendingPool
   * @param _asset The address of collateral external asset
   *  _asset = 0x0000000000000000000000000000000000000000 means to use ETH as collateral
   * @param _amount The amount of collateral internal asset
   * @return The amount of collateral external asset
   */
  function withdrawOnLiquidation(address _asset, uint256 _amount)
    external
    virtual
    returns (uint256);

  /**
   * @dev Get yield based on strategy and re-deposit
   * - Caller is anyone
   */
  function processYield() external virtual;

  /**
   * @dev Get price per share based on yield strategy
   * @return The value of price per share
   */
  function pricePerShare() external view virtual returns (uint256);

  /**
   * @dev Set treasury address and vault fee
   * - Caller is only PoolAdmin which is set on LendingPoolAddressesProvider contract
   * @param _treasury The treasury address
   * @param _fee The vault fee which has more two decimals, ex: 100% = 100_00
   */
  function setTreasuryInfo(address _treasury, uint256 _fee) public payable virtual onlyAdmin {
    require(_treasury != address(0), Errors.VT_TREASURY_INVALID);
    require(_fee <= 30_00, Errors.VT_FEE_TOO_BIG);
    _treasuryAddress = _treasury;
    _vaultFee = _fee;

    emit SetTreasuryInfo(_treasury, _fee);
  }

  /**
   * @dev deposit collateral asset to lending pool
   * @param _asset The address of collateral external asset
   * @param _amount Collateral external asset amount
   * @param _user The address of user
   */
  function _deposit(
    address _asset,
    uint256 _amount,
    address _user
  ) internal {
    if (_asset != address(0)) {
      // asset = ERC20
      require(msg.value == 0, Errors.VT_COLLATERAL_DEPOSIT_INVALID);
    } else {
      // asset = ETH
      require(msg.value == _amount, Errors.VT_COLLATERAL_DEPOSIT_REQUIRE_ETH);
    }
    // Deposit asset to vault and receive stAsset
    // Ex: if user deposit 100ETH, this will deposit 100ETH to Lido and receive 100stETH
    (address _stAsset, uint256 _stAssetAmount) = _depositToYieldPool(_asset, _amount);

    // Deposit stAsset to lendingPool, then user will get aToken of stAsset
    ILendingPool(_addressesProvider.getLendingPool()).deposit(_stAsset, _stAssetAmount, _user, 0);

    emit DepositCollateral(_asset, _user, _amount);
  }

  /**
   * @dev Deposit collateral external asset to yield pool based on strategy and receive collateral internal asset
   * @param _asset The address of collateral external asset
   * @param _amount The amount of collateral external asset
   * @return The address of collateral internal asset
   * @return The amount of collateral internal asset
   */
  function _depositToYieldPool(address _asset, uint256 _amount)
    internal
    virtual
    returns (address, uint256);

  /**
   * @dev Withdraw collateral internal asset from yield pool based on strategy and deliver collateral external asset
   * @param _asset The address of collateral external asset
   * @param _amount The withdrawal amount of collateral internal asset
   * @param _to The address of receiving collateral external asset
   * @return The amount of collateral external asset
   */
  function _withdrawFromYieldPool(
    address _asset,
    uint256 _amount,
    address _to
  ) internal virtual returns (uint256);

  /**
   * @dev Get Withdrawal amount of collateral internal asset based on strategy
   * @param _asset The address of collateral external asset
   * @param _amount The withdrawal amount of collateral external asset
   * @return The address of collateral internal asset
   * @return The withdrawal amount of collateral internal asset
   */
  function _getWithdrawalAmount(address _asset, uint256 _amount)
    internal
    view
    virtual
    returns (address, uint256);
}

