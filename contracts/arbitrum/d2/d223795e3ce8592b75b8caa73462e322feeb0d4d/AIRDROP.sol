import "./IERC20.sol";
import "./SafeMath.sol";

pragma solidity ^0.8.0;

contract AIRDROP {
    using SafeMath for uint256;

    function getSum(uint256[] calldata _arr) public pure returns (uint sum) {
        bool state;
        for (uint i = 0; i < _arr.length; i++) {
            (state, sum) = sum.tryAdd(_arr[i]);
            require(state == true, "over max");
        }
    }

    function multiTransferToken(
        address _token,
        address[] calldata _addresses,
        uint256[] calldata _amounts
    ) external {
        require(
            _addresses.length == _amounts.length,
            "Lengths of Addresses and Amounts NOT EQUAL"
        );
        IERC20 token = IERC20(_token);
        uint _amountSum = getSum(_amounts);
        require(
            token.allowance(msg.sender, address(this)) >= _amountSum,
            "Need Approve ERC20 token"
        );

        for (uint8 i; i < _addresses.length; i++) {
            token.transferFrom(msg.sender, _addresses[i], _amounts[i]);
        }
    }
}

