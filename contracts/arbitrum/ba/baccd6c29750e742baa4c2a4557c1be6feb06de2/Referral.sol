// SPDX-License-Identifier: MIT

pragma solidity =0.8.17;
pragma experimental ABIEncoderV2;

import "./Ownable.sol";
import "./ERC20_IERC20.sol";
import "./SafeERC20.sol";

contract Referral is Ownable {
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    address public operator;

    /* ========== MODIFIERS ========== */

    modifier onlyOperator() {
        require(msg.sender == operator, 'Referral: !operator');
        _;
    }

    /* ========== CONSTRUCTOR ========== */

    constructor (address _operator) {
        operator = _operator;
    }


    /* ========== VIEWS ========== */

    /* ========== PUBLIC FUNCTIONS ========== */

    /* ========== INTERNAL FUNCTIONS ========== */

    function _isEnoughMoney(address _token, uint256[] memory _amounts) internal view returns (bool) {
        uint256 _totalCashOut = 0;
        for (uint256 i = 0; i < _amounts.length; i++) {
            _totalCashOut += _amounts[i];
        }
        return IERC20(_token).balanceOf(address(this)) >= _totalCashOut;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function distribute(address _token, address[] memory _accounts, uint256[] memory _amounts) public onlyOperator {
        require(_accounts.length == _amounts.length, "Referral: invalid length");
        require(_isEnoughMoney(_token, _amounts), "Referral: !enough money");
        for (uint256 i = 0; i < _accounts.length; i++) {
            if (_accounts[i] != address(0) && _amounts[i] > 0) {
                IERC20(_token).safeTransfer(_accounts[i], _amounts[i]);
            }
        }
        emit Distributed(_token, _accounts, _amounts);
    }

    function setOperator(address _newOperator) external onlyOwner {
        address oldOperator = operator;
        operator = _newOperator;
        emit OperatorChanged(oldOperator, _newOperator);
    }

    // EVENTS
    event Distributed(address token, address[] accounts, uint256[] amounts);
    event OperatorChanged(address indexed oldOperator, address indexed newOperator);
}
