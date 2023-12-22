// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./IQiDaoVault.sol";
import "./ERC20_IERC20.sol";
import "./extensions_IERC20Metadata.sol";
import "./SafeERC20.sol";
import "./UUPSUpgradeable.sol";
// import "forge-std/console.sol";

/// @title QiDao Simple Borrow Contract
/// @dev This is an abstract contract that must be implemented for each vault type.
abstract contract QiDaoSimpleBorrower is UUPSUpgradeable {
  using SafeERC20 for IERC20;

  function _authorizeUpgrade(address) internal override onlyOwner {}

  // Constants
  enum RebalanceType { NONE, BORROW, REPAY }
  uint constant PRICE_PRECISION = 1e8; // qidao oracles are USD with 1e8 decimals
  uint constant CDR_PRECISION = 1e4; // 4 decimals of precision, e.g. 11500 = 115%

  // Immutables (set by child contract)

  address immutable owner; // Owner of this contract
  address immutable maiAddress; // Address of the MAI token
  address immutable tokenAddress; // Address of the underlying token in the vault
  address immutable qiAddress; // Address of the QI token
  address immutable vaultAddress; // QiDao vault address
  address immutable gelatoOpsAddress;
  address immutable alternateKeeperAddress;

  // Storage variables: do not change order or remove, as this contract must be upgradeable

  // folder stuff
  uint public vaultId; // QiDao vault ID (created upon initialization)
  uint public targetCdr; // target CDR
  uint public maxCdr; // borrow more when above this CDR

  // Modifiers

  modifier onlyOwner() {
    require(owner == msg.sender, "not owner");
    _;
  }

  modifier onlyKeeper() {
    require(owner == msg.sender || gelatoOpsAddress == msg.sender || alternateKeeperAddress == msg.sender, "not owner, gelato, or alternate keeper");
    _;
  }

  modifier onlyInitialized() {
    require(vaultId != 0, "not initialized");
    _;
  }

  // Initialization

  // sets immutable variables only, as this will be deployed behind a proxy
  constructor(address _owner, address _maiAddress, address _vaultAddress, address _tokenAddress, address _qiAddress, address _gelatoOpsAddress, address _alternateKeeperAddress) {
    owner = _owner;
    maiAddress = _maiAddress;
    vaultAddress = _vaultAddress;
    tokenAddress = _tokenAddress;
    qiAddress = _qiAddress;
    gelatoOpsAddress = _gelatoOpsAddress;
    alternateKeeperAddress = _alternateKeeperAddress;
  }

  /// @notice create a vault and initialize storage variables
  function initialize(
    uint _targetCdr,
    uint _maxCdr
  ) external onlyOwner {
    require(vaultId == 0, "already initialized");
    _setTargetCdr(_targetCdr);
    _setMaxCdr(_maxCdr);
    IERC20(tokenAddress).safeApprove(vaultAddress, type(uint).max);
    IERC20(maiAddress).safeApprove(vaultAddress, type(uint).max);
    vaultId = IQiDaoVault(vaultAddress).createVault();
  }

  // External

  /// @param _vaultId new vault ID (must be owned by this contract)
  function setVaultId(uint _vaultId) external onlyOwner {
    require(vaultId == 0, "already initialized");
    vaultId = _vaultId;
  }

  /// @param _targetCdr target collateral:debt ratio with 4 decimals of precision, e.g. "11500" for 115%
  function setTargetCdr(uint _targetCdr) external onlyOwner onlyInitialized {
    _setTargetCdr(_targetCdr);
  }

  /// @param _maxCdr max collateral:debt ratio with 4 decimals of precision, e.g. "11500" for 115%
  function setMaxCdr(uint _maxCdr) external onlyOwner onlyInitialized {
    _setMaxCdr(_maxCdr);
  }

  /// @notice Rebalances the vault based on the target CDR by either borrowing or repaying if necessary.
  function rebalance() external onlyKeeper onlyInitialized {
    RebalanceType rt = _getRebalanceType();
    require(rt != RebalanceType.NONE, "no rebalance needed");

    if (rt == RebalanceType.BORROW) {
      _borrow();
    } else if (rt == RebalanceType.REPAY) {
      _repay();
    }
  }

  function checkRebalanceGelato() external view returns (bool canExec, bytes memory execPayload) {
    RebalanceType rt = _getRebalanceType();

    if (rt != RebalanceType.NONE) {
      canExec = true;
      execPayload = abi.encodeWithSelector(QiDaoSimpleBorrower.rebalance.selector);
    }
  }

  /// @notice deposits collateral tokens from this contract to the QiDao vault.
  /// @param _amount amount of tokens to deposit
  function depositCollateral(uint _amount) external onlyOwner onlyInitialized {
    _depositCollateral(_amount);
  }

  function repay(uint _amount) external onlyOwner onlyInitialized {
    require(_amount <= maiBalance(), "not enough mai to repay");
    IQiDaoVault(vaultAddress).payBackToken(vaultId, _amount);
  }

  /// @notice withdraws collateral tokens from the QiDao vault.
  function withdrawCollateral(uint _amount) external onlyOwner onlyInitialized {
    _withdrawCollateral(_amount);
  }

  /// @notice withdraws collateral tokens from the QiDao vault, first repaying as much MAI
  /// is necessary in order to keep the CDR at the targetMaxCdrAvg
  function withdrawCollateralWithRepay(uint _amount) external onlyOwner onlyInitialized {
    _withdrawCollateralWithRepay(_amount);
  }

  /// @notice withdraws collateral tokens from this contract.
  function withdrawTokens(uint _amount) external onlyOwner onlyInitialized {
    require(_amount <= tokenBalance(), "not enough tokens to withdraw");
    IERC20(tokenAddress).safeTransfer(owner, _amount);
  }

  /// @notice withdraws full balance of Qi tokens from this contract.
  function withdrawQi(uint _amount) external onlyOwner onlyInitialized {
    require(_amount <= qiBalance(), "not enough qi to withdraw");
    IERC20(qiAddress).safeTransfer(owner, _amount);
  }

  /// @notice withdraws full balance of MAI tokens from this contract.
  function withdrawMai(uint _amount) external onlyOwner onlyInitialized {
    require(_amount <= maiBalance(), "not enough MAI to withdraw");
    IERC20(maiAddress).safeTransfer(owner, _amount);
  }

  /// @notice withdraw the balance of a token from the contract
  /// @param _token token address
  /// @param _amount token amount
  function rescueToken(address _token, uint _amount) external onlyOwner {
    if (_token == address(0)) {
      payable(owner).transfer(_amount);
    } else {
      IERC20(_token).safeTransfer(owner, _amount);
    }
  }

  /// @notice "bails out" by transferring the underlying vault NFT to the owner
  /// after this function is called, the folder can be initialized again if needed
  function bailout() external onlyOwner onlyInitialized {
    IQiDaoVault(vaultAddress).safeTransferFrom(address(this), owner, vaultId);
    vaultId = 0; // clear vaultId
  }

  // Public

  function targetMaxCdrAvg() view public returns (uint) {
    if (targetCdr == type(uint).max || maxCdr == type(uint).max) {
      return type(uint).max;
    }

    return (targetCdr + maxCdr) / 2;
  }

  /// @return amount of MAI that can be borrowed based on the CDR that we are targeting.
  /// The return value of this function will also be capped at the current debt ceiling of vault.
  /// Expressed with 1e18 decimals of precision.
  function availableBorrows() view public returns (uint) {
    uint borrowsBasedOnCdr = _availableBorrowsByTargetMaxCdrAvg();
    uint borrowsBasedOnMai = IQiDaoVault(vaultAddress).getDebtCeiling();

    // return the min
    return borrowsBasedOnCdr < borrowsBasedOnMai ? borrowsBasedOnCdr : borrowsBasedOnMai;
  }

  /// @return number of underlying tokens in this contract
  function tokenBalance() view public returns (uint) {
    return IERC20(tokenAddress).balanceOf(address(this));
  }

  /// @return number of Qi tokens in this contract
  function qiBalance() view public returns (uint) {
    return IERC20(qiAddress).balanceOf(address(this));
  }

  /// @return number of MAI tokens in this contract
  function maiBalance() view public returns (uint) {
    return IERC20(maiAddress).balanceOf(address(this));
  }

  /// @return amount of MAI debt in the QiDao vault
  function vaultDebt() view public returns (uint) {
    return IQiDaoVault(vaultAddress).vaultDebt(vaultId);
  }

  /// @return amount of collateral locked in the QiDao vault
  function vaultCollateral() view public returns (uint) {
    return IQiDaoVault(vaultAddress).vaultCollateral(vaultId);
  }

  /// @return current CDR for this vault, expressed with CDR_PRECISION decimals of precision
  function vaultCdr() view public returns (uint) {
    uint debt = vaultDebt();
    return debt == 0 ? type(uint).max : _vaultCollateralValue() * CDR_PRECISION / debt;
  }

  // Internal

  function _borrow() internal {
    uint borrowAmount = availableBorrows();
    require(borrowAmount > 0, "no borrows available");
    IQiDaoVault(vaultAddress).borrowToken(vaultId, borrowAmount);
  }

  function _repay() internal {
    uint targetDebt = _vaultCollateralValue() * CDR_PRECISION / targetMaxCdrAvg();
    uint currentDebt = vaultDebt();
    require(targetDebt < currentDebt, "no need to repay");
    uint targetAmountToRepay = currentDebt - targetDebt;
    uint maiBal = maiBalance();
    require(maiBal > 0, "no tokens to repay with");
    uint amountToRepay = maiBal < targetAmountToRepay ? maiBal : targetAmountToRepay;
    IQiDaoVault(vaultAddress).payBackToken(vaultId, amountToRepay);
  }

  function _setTargetCdr(uint _targetCdr) internal {
    require(_targetCdr > _vaultMinimumCdr(), "targetCdr too low");
    targetCdr = _targetCdr;
  }

  function _setMaxCdr(uint _maxCdr) internal {
    require(_maxCdr > _vaultMinimumCdr(), "maxCdr too low");
    require(_maxCdr > targetCdr, "maxCdr must be gt targetCdr");
    maxCdr = _maxCdr;
  }

  function _depositCollateral(uint _amount) internal {
    require(_amount > 0, "must deposit more than 0 tokens");
    require(_amount <= tokenBalance(), "not enough collateral to deposit");
    IQiDaoVault(vaultAddress).depositCollateral(vaultId, _amount);
  }

  function _withdrawCollateral(uint _amount) internal {
    IQiDaoVault(vaultAddress).withdrawCollateral(vaultId, _amount);
  }

  function _withdrawCollateralWithRepay(uint _amount) internal {
    require(_amount < vaultCollateral(), "can't withdraw more than balance");
    uint newCollateralAmount = vaultCollateral() - _amount;
    uint maxTotalBorrowsInCollateral = newCollateralAmount * _collateralPrice() / PRICE_PRECISION * CDR_PRECISION / targetMaxCdrAvg();

    uint curDebt = vaultDebt();

    if (curDebt > maxTotalBorrowsInCollateral) {
      uint amountToRepay = (curDebt - maxTotalBorrowsInCollateral);
      amountToRepay = amountToRepay + (amountToRepay * IQiDaoVault(vaultAddress).closingFee() / 10000);
      IQiDaoVault(vaultAddress).payBackToken(vaultId, amountToRepay);
    }

    // uint debt = vaultDebt();
    // return maxTotalBorrowsInCollateral > debt ? maxTotalBorrowsInCollateral - debt : 0;

    IQiDaoVault(vaultAddress).withdrawCollateral(vaultId, _amount);
  }

  function _getRebalanceType() view internal returns (RebalanceType rt) {
    if (vaultId == 0) {
      return RebalanceType.NONE; // not initialized
    }

    if (vaultCollateral() == 0) {
      return RebalanceType.NONE; // vault has no collateral
    }

    uint cdr = vaultCdr();

    if ((cdr > maxCdr) && (availableBorrows() > 0)) {
      rt = RebalanceType.BORROW;
    } else if (cdr < targetCdr && maiBalance() > 0) {
      rt = RebalanceType.REPAY;
    }
  }

  function _collateralPrice() view internal returns (uint) {
    uint price = IQiDaoVault(vaultAddress).getEthPriceSource();
    uint decimals = _tokenDecimals();

    if (decimals < 18) {
      return price * (10 ** (18 - decimals));
    } else {
      return price;
    }
  }

  /// @return approximate USD value of the vault collateral, expressed with 1e18 decimals of precision
  function _vaultCollateralValue() view internal returns (uint) {
    return vaultCollateral() * _collateralPrice() / PRICE_PRECISION;
  }

  /// @return Minimum CDR for this vault, expressed with CDR_PRECISION decimals of precision
  function _vaultMinimumCdr() view internal returns (uint) {
    return IQiDaoVault(vaultAddress)._minimumCollateralPercentage() * CDR_PRECISION / 1e2;
  }

  function _maiBalance() view internal returns (uint) {
    return IERC20(maiAddress).balanceOf(address(this));
  }

  function _tokenDecimals() view internal returns (uint) {
    return IERC20Metadata(tokenAddress).decimals();
  }

  function _availableBorrowsByTargetMaxCdrAvg() view internal returns (uint) {
    uint maxTotalBorrowsInCollateral = _vaultCollateralValue() * CDR_PRECISION / targetMaxCdrAvg();
    uint debt = vaultDebt();
    return maxTotalBorrowsInCollateral > debt ? maxTotalBorrowsInCollateral - debt : 0;
  }

  // allow receiving NFT xfer
  function onERC721Received(address, address, uint256, bytes calldata) pure external returns (bytes4) {
    return QiDaoSimpleBorrower.onERC721Received.selector;
  }
}

