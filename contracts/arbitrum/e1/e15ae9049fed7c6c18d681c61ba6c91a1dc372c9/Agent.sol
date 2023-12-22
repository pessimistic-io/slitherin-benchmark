// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

import { IAgent } from "./IAgent.sol";
import { AgentStorage } from "./AgentStorage.sol";
import { OwnerPausable } from "./OwnerPausable.sol";
import { BlockContext } from "./BlockContext.sol";
import { UserAccount } from "./UserAccount.sol";
import { IUserAccount } from "./IUserAccount.sol";
import { IVault } from "./IVault.sol";
import { IClearingHouse } from "./IClearingHouse.sol";
import { IAccountBalance } from "./IAccountBalance.sol";
import { IERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { ClonesUpgradeable } from "./ClonesUpgradeable.sol";
import { AddressUpgradeable } from "./AddressUpgradeable.sol";
import { SafeMathUpgradeable } from "./SafeMathUpgradeable.sol";
import { SignedSafeMathUpgradeable } from "./SignedSafeMathUpgradeable.sol";
import { PerpSafeCast } from "./PerpSafeCast.sol";
import { PerpMath } from "./PerpMath.sol";
import { TransferHelper } from "./TransferHelper.sol";

// never inherit any new stateful contract. never change the orders of parent stateful contracts
contract Agent is IAgent, BlockContext, OwnerPausable, AgentStorage {
    //
    using SafeMathUpgradeable for uint256;
    using SignedSafeMathUpgradeable for int256;
    using PerpSafeCast for uint256;
    using PerpSafeCast for uint256;
    using PerpMath for uint256;
    using PerpMath for int256;
    //
    modifier onlyAdmin() {
        // NO_NA: not priceAdmin
        require(_msgSender() == _admin, "NO_NA");
        _;
    }

    receive() external payable {}

    function initialize(address clearingHouse) external initializer {
        __OwnerPausable_init();
        //
        _admin = _msgSender();
        _clearingHouse = clearingHouse;
        _vault = IClearingHouse(_clearingHouse).getVault();
        _accountBalance = IClearingHouse(_clearingHouse).getAccountBalance();
        _txFee = 0.0003 ether;
        _minClaimBalance = 10000 ether;
    }

    function setClearingHouse(address clearingHouseArg) external onlyOwner {
        _clearingHouse = clearingHouseArg;
        _vault = IClearingHouse(_clearingHouse).getVault();
        _accountBalance = IClearingHouse(_clearingHouse).getAccountBalance();
    }

    function setAdmin(address adminArg) external onlyOwner {
        _admin = adminArg;
    }

    function setUserAccountTpl(address userAccountTplArg) external onlyOwner {
        _userAccountTpl = userAccountTplArg;
    }

    function setUserAccountImpl(address userAccountImplArg) external onlyOwner {
        _userAccountImpl = userAccountImplArg;
    }

    function setTxFee(uint256 txFeeArg) external onlyOwner {
        _txFee = txFeeArg;
    }

    function setMinClaimBalance(uint256 minClaimBalance) external onlyOwner {
        _minClaimBalance = minClaimBalance;
    }

    function getAdmin() external view returns (address admin) {
        admin = _admin;
    }

    function getUserAccountTpl() external view returns (address userAccountTpl) {
        userAccountTpl = _userAccountTpl;
    }

    function getUserAccountImpl() external view returns (address userAccountImpl) {
        userAccountImpl = _userAccountImpl;
    }

    function getTxFee() external view returns (uint256 txFee) {
        txFee = _txFee;
    }

    function getMinClaimBalance() external view returns (uint256 minClaimBalance) {
        minClaimBalance = _minClaimBalance;
    }

    function getTraderBalance() external view returns (int256 traderBalance) {
        traderBalance = _traderBalance;
    }

    function getUserAccount(address trader) external view returns (address account) {
        account = _userAccountMap[trader];
    }

    function isUserNonceUsed(address trader, uint256 nonce) external view returns (bool used) {
        address account = _userAccountMap[trader];
        if (account != address(0)) {
            used = _traderNonceMap[account][nonce];
        }
    }

    function getBalance(address trader) external view returns (int256 balance) {
        address account = _userAccountMap[trader];
        if (account != address(0)) {
            balance = _balanceMap[account];
        }
    }

    function getFreeBalanceAndCollateral(
        address trader,
        address baseToken
    ) external view returns (int256 balance, int256 freeCollateral) {
        address account = _userAccountMap[trader];
        if (account != address(0)) {
            balance = _balanceMap[account];
            freeCollateral = IVault(_vault).getFreeCollateral(account, baseToken).toInt256();
        }
    }

    function approveMaximumTo(address token, address delegate) external onlyOwner {
        IERC20Upgradeable(token).approve(delegate, type(uint256).max);
    }

    function _getOrCreateUserAccount(address trader) internal returns (address) {
        address account = _userAccountMap[trader];
        if (account == address(0)) {
            bytes memory _initializationCalldata = abi.encodeWithSignature(
                "initialize(address,address)",
                trader,
                address(this)
            );
            account = ClonesUpgradeable.clone(_userAccountTpl);
            AddressUpgradeable.functionCall(account, _initializationCalldata);
            //
            _userAccountMap[trader] = account;
            // emit
            emit AccountCreated(trader, account);
        }
        return account;
    }

    function _requireTraderNonce(address account, uint256 nonce) internal {
        require(_traderNonceMap[account][nonce] == false, "A_IN");
        _traderNonceMap[account][nonce] = true;
    }

    function _modifyAccountBalance(address account, int256 amount) internal {
        _balanceMap[account] = _balanceMap[account].add(amount);
        _traderBalance = _traderBalance.add(amount);
    }

    function _vaultDeposit(uint256 nonce, address account, address baseToken, uint256 amount) internal {
        if (amount > 0) {
            address vault = _vault;
            address token = IVault(vault).getSettlementToken();
            //deposit
            if (token != IVault(vault).getWETH9()) {
                IVault(vault).depositFor(account, token, amount, baseToken);
            } else {
                IVault(vault).depositEtherFor{ value: amount }(account, baseToken);
            }
            _modifyAccountBalance(account, amount.neg256());
            emit VaultDeposited(nonce, account, baseToken, token, amount);
        }
    }

    function _vaultWithdrawAll(uint256 nonce, address account, address baseToken) internal {
        // check base size id zero value
        address accountBalance = _accountBalance;
        int256 positionSize = IAccountBalance(accountBalance).getTotalPositionSize(account, baseToken);
        if (positionSize == 0) {
            (address token, uint256 amount) = IUserAccount(account).withdrawAll(_clearingHouse, baseToken);
            _modifyAccountBalance(account, amount.toInt256());
            emit VaultWithdraw(nonce, account, baseToken, token, amount);
        }
    }

    function _vaultWithdraw(uint256 nonce, address account, address baseToken, uint256 amountArg) internal {
        // check base size id zero value
        (address token, uint256 amount) = IUserAccount(account).withdraw(_clearingHouse, baseToken, amountArg);
        _modifyAccountBalance(account, amount.toInt256());
        emit VaultWithdraw(nonce, account, baseToken, token, amount);
    }

    function _deposit(uint256 nonce, address account, uint256 amount) internal {
        if (amount > 0) {
            address vault = _vault;
            address token = IVault(vault).getSettlementToken();
            _modifyAccountBalance(account, amount.toInt256());
            emit Deposited(nonce, account, token, amount);
        }
    }

    function _withdraw(uint256 nonce, address account, uint256 amount) internal {
        if (amount > 0) {
            address vault = _vault;
            address token = IVault(vault).getSettlementToken();
            _modifyAccountBalance(account, amount.neg256());
            emit Withdraw(nonce, account, token, amount);
        }
    }

    function _chargeFee(uint256 nonce, address account, uint256 amount) internal {
        if (amount > 0) {
            address vault = _vault;
            address token = IVault(vault).getSettlementToken();
            _modifyAccountBalance(account, amount.neg256());
            _balanceMap[address(this)] = _balanceMap[address(this)].add(amount.toInt256());
            emit FeeCharged(nonce, account, token, amount);
        }
    }

    function depositAndOpenPositionFor(
        uint256 nonce,
        address trader,
        address baseToken,
        bool isBaseToQuote,
        uint256 quoteAmount,
        uint256 depositAmount
    ) external onlyAdmin returns (bool) {
        // get or create account
        address account = _getOrCreateUserAccount(trader);
        _requireTraderNonce(account, nonce);
        // chrage fee
        _chargeFee(nonce, account, _txFee);
        // A_IANF: invalid amount and fee
        require(depositAmount >= _txFee, "A_IANF");
        //deposit
        _deposit(nonce, account, depositAmount);
        _vaultDeposit(nonce, account, baseToken, depositAmount.sub(_txFee));
        //open position
        IUserAccount(account).openPosition(_clearingHouse, baseToken, isBaseToQuote, quoteAmount);
        // withdraw all
        _vaultWithdrawAll(nonce, account, baseToken);
        // A_IB: insufficient balance
        require(_balanceMap[account] >= 0, "A_IB");
        return true;
    }

    function openPositionFor(
        uint256 nonce,
        address trader,
        address baseToken,
        bool isBaseToQuote,
        uint256 quoteAmount,
        uint256 collateralAmount
    ) external onlyAdmin returns (bool) {
        // get or create account
        address account = _getOrCreateUserAccount(trader);
        _requireTraderNonce(account, nonce);
        // chrage fee
        _chargeFee(nonce, account, _txFee);
        //deposit
        _vaultDeposit(nonce, account, baseToken, collateralAmount);
        //open position
        IUserAccount(account).openPosition(_clearingHouse, baseToken, isBaseToQuote, quoteAmount);
        // withdraw all
        _vaultWithdrawAll(nonce, account, baseToken);
        // A_IB: insufficient balance
        require(_balanceMap[account] >= 0, "A_IB");
        return true;
    }

    function closePositionFor(uint256 nonce, address trader, address baseToken) external onlyAdmin returns (bool) {
        // get or create account
        address account = _getOrCreateUserAccount(trader);
        _requireTraderNonce(account, nonce);
        //
        _chargeFee(nonce, account, _txFee);
        // close position
        IUserAccount(account).closePosition(_clearingHouse, baseToken);
        // withdraw all
        _vaultWithdrawAll(nonce, account, baseToken);
        // A_IB: insufficient balance
        require(_balanceMap[account] >= 0, "A_IB");
        return true;
    }

    function deposit(uint256 nonce, address trader, uint256 amount) external onlyAdmin returns (bool) {
        // get or create account
        address account = _getOrCreateUserAccount(trader);
        _requireTraderNonce(account, nonce);
        // A_IANF: invalid amount and fee
        require(amount >= _txFee, "A_IANF");
        _chargeFee(nonce, account, _txFee);
        // deposit
        _deposit(nonce, account, amount);
        //
        return true;
    }

    function vaultDeposit(
        uint256 nonce,
        address trader,
        address baseToken,
        uint256 amount
    ) external onlyAdmin returns (bool) {
        // get or create account
        address account = _getOrCreateUserAccount(trader);
        _requireTraderNonce(account, nonce);
        //
        _chargeFee(nonce, account, _txFee);
        // topup
        _vaultDeposit(nonce, account, baseToken, amount);
        // A_IB: insufficient balance
        require(_balanceMap[account] >= 0, "A_IB");
        //
        return true;
    }

    function vaultWithdraw(
        uint256 nonce,
        address trader,
        address baseToken,
        uint256 amount
    ) external onlyAdmin returns (bool) {
        // get or create account
        address account = _getOrCreateUserAccount(trader);
        _requireTraderNonce(account, nonce);
        //
        _chargeFee(nonce, account, _txFee);
        // topup
        _vaultWithdraw(nonce, account, baseToken, amount);
        // A_IB: insufficient balance
        require(_balanceMap[account] >= 0, "A_IB");
        //
        return true;
    }

    function withdraw(uint256 nonce, address trader, uint256 amount) external onlyAdmin returns (bool) {
        // get or create account
        address account = _getOrCreateUserAccount(trader);
        _requireTraderNonce(account, nonce);
        // withdraw
        _chargeFee(nonce, account, _txFee);
        _withdraw(nonce, account, amount);
        // A_IB: insufficient balance
        require(_balanceMap[account] >= 0, "A_IB");
        //
        return true;
    }

    function claimReward(uint256 nonce, address trader) external onlyAdmin returns (bool) {
        // get or create account
        address account = _getOrCreateUserAccount(trader);
        _requireTraderNonce(account, nonce);
        uint256 amount = IUserAccount(account).claimReward(_clearingHouse);
        // A_NCMA: not claim min amount
        require(amount >= _minClaimBalance, "A_NCMA");
        emit RewardClaimed(nonce, account, amount);
        //
        return true;
    }

    //
    function emergencyWithdrawEther(uint256 amount) external onlyOwner {
        TransferHelper.safeTransferETH(_msgSender(), amount);
    }

    function withdrawTxFee(uint256 amount) external onlyOwner {
        _balanceMap[address(this)] = _balanceMap[address(this)].sub(amount.toInt256());
        TransferHelper.safeTransferETH(_msgSender(), amount);
        require(_balanceMap[address(this)] >= 0, "A_IB");
        emit TxFeeWithdraw(amount);
    }
}

