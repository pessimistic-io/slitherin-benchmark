pragma solidity >=0.8.0;

import {IWETH} from "./IWETH.sol";
import {IETHUnwrapper} from "./IETHUnwrapper.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";

contract ETHUnwrapper is IETHUnwrapper {

    IWETH private immutable weth;

    constructor(address _weth) {
        require(_weth != address(0), "Invalid weth address");
        weth = IWETH(_weth);
    }

    function unwrap(uint256 _amount, address _to) external {
        SafeTransferLib.safeTransferFrom(address(weth), msg.sender, address(this), _amount);
        weth.withdraw(_amount);
        // transfer out all ETH, include amount tranfered in by accident. We don't want ETH to stuck here forever
        SafeTransferLib.safeTransferETH(_to, address(this).balance);
    }

    receive() external payable {
        require(msg.sender == address(weth));
    }
}

