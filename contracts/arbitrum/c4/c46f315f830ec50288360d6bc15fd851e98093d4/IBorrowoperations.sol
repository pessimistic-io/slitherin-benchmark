// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "./IUnboundBase.sol";
interface IBorrowoperations is IUnboundBase{

    enum BorrowerOperation {
        openAccount,
        closeAccount,
        adjustAccount
    }

    event AccountCreated(address indexed _borrower, uint arrayIndex);
    event AccountUpdated(address indexed _borrower, uint _debt, uint _coll, BorrowerOperation operation);
    event UNDBorrowingFeePaid(address indexed _borrower, uint _UNDFee);

    function governanceFeeAddress() external view returns (address);
    function factory() external view returns(address);

    function openAccount(uint256 _maxFeePercentage, uint256 _colAmount, uint256 _UNDAmount, address _upperHint, address _lowerHint) external;

    function addColl(uint256 _collDeposit, address _upperHint, address _lowerHint) external;
    function withdrawColl(uint _collWithdrawal, address _upperHint, address _lowerHint) external;
    function withdrawUND(uint _maxFeePercentage, uint _UNDAmount, address _upperHint, address _lowerHint) external;
    function repayUND(uint _UNDAmount, address _upperHint, address _lowerHint) external;
    function adjustAccount(uint _maxFeePercentage, uint256 _collDeposit, uint _collWithdrawal, uint _UNDChange, bool _isDebtIncrease, address _upperHint, address _lowerHint) external;

    function closeAccount() external;

    function claimCollateral() external;
}
