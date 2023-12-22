// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./IERC20.sol";
import "./IFeeBankCharger.sol";
import "./FeeBank.sol";

contract FeeBankCharger is IFeeBankCharger {
    error OnlyFeeBankAccess();
    error NotEnoughCredit();

    IFeeBank public immutable feeBank;
    mapping(address => uint256) private _creditAllowance;

    modifier onlyFeeBank() {
        if (msg.sender != address(feeBank)) revert OnlyFeeBankAccess();
        _;
    }

    constructor(IERC20 token) {
        feeBank = new FeeBank(this, token, msg.sender);
    }

    function availableCredit(address account) external view returns (uint256) {
        return _creditAllowance[account];
    }

    function increaseAvailableCredit(address account, uint256 amount) external onlyFeeBank returns (uint256 allowance) {
        allowance = _creditAllowance[account];
        unchecked {
            allowance += amount;  // overflow is impossible due to limited _token supply
        }
        _creditAllowance[account] = allowance;
    }

    function decreaseAvailableCredit(address account, uint256 amount) external onlyFeeBank returns (uint256 allowance) {
        allowance = _creditAllowance[account];
        allowance -= amount;  // checked math is needed to prevent underflow
        _creditAllowance[account] = allowance;
    }

    function _chargeFee(address account, uint256 fee) internal {
        if (fee > 0) {
            uint256 currentAllowance = _creditAllowance[account];
            if (currentAllowance < fee) revert NotEnoughCredit();
            unchecked {
                _creditAllowance[account] = currentAllowance - fee;
            }
        }
    }
}

