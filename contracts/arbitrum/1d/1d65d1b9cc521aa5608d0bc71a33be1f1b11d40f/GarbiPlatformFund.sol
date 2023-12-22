// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;

import "./SafeMath.sol";
import "./IERC20.sol";
import "./Ownable.sol";

contract GarbiPlatformFund is Ownable {

    using SafeMath for uint256;

    function releasePlatformFund(IERC20 token) public onlyOwner {
        token.transfer(owner(), token.balanceOf(address(this)));
    }

}
