// SPDX-License-Identifier: Unlicense

pragma solidity >=0.8.0 <=0.8.19;

import "./IERC20.sol";
import "./StorageSlot.sol";

interface IWETH9 is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

contract Wrapper {
    bytes32 private constant TOKEN_SLOT = 0xeac7df60c84c961417af33f2e8f3aa7164a2805a4a8f2fd7ce31a819fcb1462c;  // keccak256("Wrapper.token")
    address internal immutable OWNER;

    constructor(address owner) {
        OWNER = owner;
    }

    function initialize(IWETH9 _token) public payable {
        require(msg.sender == OWNER || address(this) == OWNER);
        StorageSlot.getAddressSlot(TOKEN_SLOT).value = address(_token);
    }

    receive() external payable {}

    function wrap(address to) public payable {
        IWETH9 _token = IWETH9(StorageSlot.getAddressSlot(TOKEN_SLOT).value);
        _token.deposit{value: address(this).balance}();
        _token.transfer(to, _token.balanceOf(address(this)));
    }

    function unwrap(address payable to, bytes calldata data) public payable {
        IWETH9 _token = IWETH9(StorageSlot.getAddressSlot(TOKEN_SLOT).value);
        _token.withdraw(_token.balanceOf(address(this)));
        (bool success,) = to.call{value: address(this).balance}(data);
        require(success);
    }
}

