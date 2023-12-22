// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./OFTV2.sol";
import "./SafeERC20.sol";
import "./IERC20.sol";

contract BullXToken is OFTV2 {
    using SafeERC20 for IERC20;
    
    constructor(address _lzEndpoint) OFTV2("BullX", "BullX", 9, _lzEndpoint) {
        _mint(msg.sender, 1 ether);
    }

    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }

    // function sendToSelf(uint _chainId, uint _amount) external payable {
    //     sendFrom{value: msg.value}(
    //         msg.sender, 
    //         _chainId, 
    //         bytes32(abi.encodePacked(msg.sender)), 
    //         _amount, 
    //         ICommonOFT.LzCallParams(payable(msg.sender), address(0), new bytes(0)));
    // }

}
