// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "./SafeERC20.sol";

import "./ICollSurplusPool.sol";
import "./IAccountManager.sol";

import "./Initializable.sol";

contract CollSurplusPool is ICollSurplusPool, Initializable{
    using SafeERC20 for IERC20;

    address public borrowerOperations;
    address public accountManager;

    // deposited collateral tracker
    uint256 internal _collateral;
    // Collateral surplus claimable by account owners
    mapping (address => uint) internal balances;

    event CollBalanceUpdated(address indexed _account, uint _newBalance);
    event CollateralSent(address _to, uint _amount);

    function initialize(address _accountManager, address _borrowerOperations) public initializer {
        accountManager = _accountManager;
        borrowerOperations = _borrowerOperations;
    }

    /* Returns the collateral state variable at MainPool address.
       Not necessarily equal to the raw ether balance - ether can be forcibly sent to contracts. */
    function getTotalCollateral() external view override returns (uint) {
        return _collateral;
    }

    function getUserCollateral(address _account) external view override returns (uint) {
        return balances[_account];
    }

    // --- Pool functionality ---

    function accountSurplus(address _account, uint _amount) external override {
        _requireCallerIsAccountManager();

        uint newAmount = balances[_account] + _amount;
        balances[_account] = newAmount;

        _collateral = _collateral + _amount;

        emit CollBalanceUpdated(_account, newAmount);
    }   

    function claimColl(IERC20 _depositToken, address _account) external override {
        _requireCallerIsBorrowerOperations();
        uint claimableColl = balances[_account];
        require(claimableColl > 0, "CollSurplusPool: No collateral available to claim");

        balances[_account] = 0;
        emit CollBalanceUpdated(_account, 0);

        _collateral = _collateral - claimableColl;
        emit CollateralSent(_account, claimableColl);

        _depositToken.safeTransfer(_account, claimableColl);
    }

    // --- 'require' functions ---

    function _requireCallerIsBorrowerOperations() internal view {
        require(
            msg.sender == borrowerOperations,
            "CollSurplusPool: Caller is not Borrower Operations");
    }

    function _requireCallerIsAccountManager() internal view {
        require(
            msg.sender == accountManager,
            "CollSurplusPool: Caller is not AccountManager");
    }
}
