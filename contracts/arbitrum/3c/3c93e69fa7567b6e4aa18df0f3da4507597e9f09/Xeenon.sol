// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./CreditLedger.sol";

contract Xeenon is CreditLedger {
  using SafeERC20 for IERC20;

  // Rate types
  uint128 public constant PERCENTAGE_RATE = 1;
  uint128 public constant FIXED_RATE = 2;

  /**
   * Component that holds values to represent different transfer options.
   * code can be 1 `PERCENTAGE_RATE` | 2 `FIXED_RATE`
   * `PERCENTAGE_RATE` is stored in values 0 - 1000 representing 0.0 - 100.0 %
   */
  struct FeeComponent {
    uint128 code;
    uint128 value;
  }

  struct BatchTransferUnit {
    address from;
    address to;
    uint256 creditAmount;
  }

  struct BatchTransferUnitWithKey {
    address from;
    address to;
    uint256 creditAmount;
    bytes32 key;
  }

  mapping(bytes32 => FeeComponent) public feeComponents;

  // In case of breach of admin wallet or user needs to take action, freeze withdraw to protect users.
  bool private withdrawFrozen;
  mapping(address => bool) private frozenWithdrawWallets;

  event Deposit(address indexed from, uint256 deposit, uint256 creditsAfter);
  event Withdraw(address indexed from, uint256 withdraw, uint256 creditsAfter);
  event Transfer(
    address indexed from,
    address indexed to,
    uint256 value,
    uint256 fee,
    uint256 fromCreditsAfter,
    uint256 toCreditsAfter,
    bytes32 key
  );
  event BatchTransfer(bytes32 indexed id);
  event SingleTransfer(bytes32 indexed id);
  event GlobalFreeze();
  event WalletFreeze(address wallet);

  constructor(
    IERC20 _acceptedToken,
    address _admin,
    address _treasuryReceiver
  ) CreditLedger(_acceptedToken, _admin, _treasuryReceiver) {
    FeeComponent storage depositFee = feeComponents['deposit'];
    depositFee.code = FIXED_RATE;
    depositFee.value = 0;

    FeeComponent storage withdrawFee = feeComponents['withdraw'];
    withdrawFee.code = FIXED_RATE;
    withdrawFee.value = 0;
  }

  // Fee component functionality

  function addFeeComponent(
    bytes32 _key,
    uint128 _code,
    uint128 _value
  ) external onlyOwner {
    require(_code == PERCENTAGE_RATE || _code == FIXED_RATE, 'Invalid code');
    if (_code == PERCENTAGE_RATE) {
      require(_key != 'deposit' && _key != 'withdraw', "Deposit/withdraw fee can't be percentage fee");
      _addPercentageRate(_key, _value);
    } else {
      _addFixedRate(_key, _value);
    }
  }

  function _addPercentageRate(bytes32 _key, uint128 _value) private {
    require(_value <= 1000, "_value can't be more than 1000.");

    FeeComponent storage feeComponent = feeComponents[_key];
    feeComponent.code = PERCENTAGE_RATE;
    feeComponent.value = _value;
  }

  function _addFixedRate(bytes32 _key, uint128 _value) private {
    FeeComponent storage feeComponent = feeComponents[_key];
    feeComponent.code = FIXED_RATE;
    feeComponent.value = _value;
  }

  function deleteFeeComponent(bytes32 _key) external onlyOwner {
    require(feeComponents[_key].code != 0, 'Key does not exist.');
    delete feeComponents[_key];
  }

  /**
   *  @notice Depositing  to receive credits.
   *  @param _amount uint256
   */
  function deposit(uint256 _amount) external {
    uint256 depositFee = feeComponents['deposit'].value;
    uint256 creditAmount = convertToCredits(_amount);

    require(creditAmount > depositFee, "Can't deposit less than fee.");

    acceptedToken.safeTransferFrom(msg.sender, address(this), _amount);

    if (depositFee > 0) {
      _addRevenue(depositFee);
      _addCredits(msg.sender, creditAmount - depositFee);
    } else {
      _addCredits(msg.sender, creditAmount);
    }

    if (!frozenWithdrawWallets[msg.sender]) {
      _freezeWalletWithdraw(msg.sender);
    }

    emit Deposit(
      msg.sender,
      convertToCredits(_amount),
      creditBalance(msg.sender)
    );
  }

  /**
   *  @notice Converting credits to DAI.
   *  @param _creditAmount uint256
   */
  function withdraw(uint256 _creditAmount) external {
    uint256 withdrawFee = feeComponents['withdraw'].value;

    require(
      creditBalance(msg.sender) >= _creditAmount,
      "You don't have enough credits."
    );
    require(_creditAmount > withdrawFee, "Can't withdraw more than fee.");
    require(!withdrawFrozen, 'Withdraws are frozen.');
    require(!frozenWithdrawWallets[msg.sender], 'Withdraws are frozen.');

    _removeCredits(msg.sender, _creditAmount);
    if (withdrawFee > 0) {
      _addRevenue(withdrawFee);
      acceptedToken.safeTransfer(
        msg.sender,
        convertFromCredits(_creditAmount - withdrawFee)
      );
    } else {
      acceptedToken.safeTransfer(msg.sender, convertFromCredits(_creditAmount));
    }

    _freezeWalletWithdraw(msg.sender);

    emit Withdraw(msg.sender, _creditAmount, creditBalance(msg.sender));
  }

  // Freezing functionality

  function freezeWithdraw() external onlyAdmin {
    withdrawFrozen = true;
    emit GlobalFreeze();
  }

  function unFreezeWithdraw() external onlyOwner {
    withdrawFrozen = false;
  }

  function isWalletFrozen(address _wallet) external view returns (bool) {
    return frozenWithdrawWallets[_wallet];
  }

  function freezeWalletWithdraw(address _wallet) external onlyRole(FREEZE) {
    _freezeWalletWithdraw(_wallet);
  }

  function freezeWalletWithdraw() external {
    _freezeWalletWithdraw(msg.sender);
  }

  function _freezeWalletWithdraw(address _wallet) private {
    frozenWithdrawWallets[_wallet] = true;
    emit WalletFreeze(_wallet);
  }

  function unFreezeWalletWithdraw(address _wallet) external onlyRole(FREEZE) {
    require(frozenWithdrawWallets[_wallet], 'Wallet was not frozen.');
    delete frozenWithdrawWallets[_wallet];
  }

  function transfer(
    address _from,
    address _to,
    uint256 _creditAmount,
    bytes32 _key,
    bytes32 _transferId
  ) external onlyRole(TRANSFER) {
    _transfer(_from, _to, _creditAmount, _key);
    emit SingleTransfer(_transferId);
  }

  function batchTransfer(
    BatchTransferUnitWithKey[] calldata _transfers,
    bytes32 _batchId
  ) external onlyRole(TRANSFER) {
    for (uint256 i = 0; i < _transfers.length; i++) {
      _transfer(_transfers[i].from, _transfers[i].to, _transfers[i].creditAmount, _transfers[i].key);
    }
    emit BatchTransfer(_batchId);
  }

  function batchTransferByKey(
    BatchTransferUnit[] calldata _transfers,
    bytes32 _key,
    bytes32 _batchId
  ) external onlyRole(TRANSFER) {
    for (uint256 i = 0; i < _transfers.length; i++) {
      _transfer(_transfers[i].from, _transfers[i].to, _transfers[i].creditAmount, _key);
    }
    emit BatchTransfer(_batchId);
  }

  /**
   * @notice Transfer credits, a fee is taken. Can only be called by admin wallet
   * @param _from address
   * @param  _to address
   * @param  _creditAmount uint256 - amount to transfer
   * @param _key string - fee component key, deciding what fee calculation is made
   */
  function _transfer(
    address _from,
    address _to,
    uint256 _creditAmount,
    bytes32 _key
  ) private {
    require(creditBalance(_from) >= _creditAmount, 'Not enough credits.');
    require(feeComponents[_key].code != 0, 'Key does not exist.');

    uint256 earnings;
    uint256 fee;
    if (feeComponents[_key].code == PERCENTAGE_RATE) {
      (earnings, fee) = _calcPercentageRateFee(
        _creditAmount,
        feeComponents[_key].value
      );
    } else if (feeComponents[_key].code == FIXED_RATE) {
      (earnings, fee) = _calcFixedRateFee(
        _creditAmount,
        feeComponents[_key].value
      );
    }

    _removeCredits(_from, _creditAmount);
    _addRevenue(fee);
    _addCredits(_to, earnings);

    emit Transfer(_from, _to, _creditAmount, fee, creditBalance(_from), creditBalance(_to), _key);
  }

  /**
   * @notice Calculates the earnings and fees of fixed rate
   * @param _amount uint256
   * @param _fixedRate uint256
   */
  function _calcFixedRateFee(uint256 _amount, uint256 _fixedRate)
    private
    pure
    returns (uint256, uint256)
  {
    if (_fixedRate > _amount) {
      return (0, _amount);
    }

    return (_amount - _fixedRate, _fixedRate);
  }

  /**
   * @notice Calculates the earnings and fees of percentage rate,
   * @param _amount uint256
   * @param _feePercentage uint256, 0 - 1000 representing 0.0 - 100.0 %
   */
  function _calcPercentageRateFee(uint256 _amount, uint256 _feePercentage)
    private
    pure
    returns (uint256, uint256)
  {
    if (_feePercentage == 0) {
      return (_amount, 0);
    }

    uint256 fee = (_amount * _feePercentage + 500) / 1000;

    // Xeenon will take a minimum fee of 1 credit for the transaction
    if (fee == 0) {
      fee = 1;
    }

    return (_amount - fee, fee);
  }
}

