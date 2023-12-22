pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./SafeERC20.sol";

contract SwaprumWithdrawals {
    using SafeERC20 for IERC20;

    address private _admin;
    IERC20 public token;

    struct payment {
        address token;
        address to;
        uint256 amount;
    }

    constructor (address admin) public {
        _admin = admin;
    }

    function withdrawal(payment[] memory _data) public {
        require(msg.sender == _admin, 'Only admin can withdrawal');

        for(uint i = 0; i < _data.length; i++) {
            token = IERC20(_data[i].token);
            token.safeTransfer(_data[i].to, _data[i].amount);
        }

    }
}
