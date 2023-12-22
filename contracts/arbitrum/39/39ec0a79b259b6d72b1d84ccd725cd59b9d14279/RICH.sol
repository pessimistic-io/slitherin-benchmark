// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

contract RichToken is ERC20, ERC20Burnable, Ownable {
    using SafeMath for uint256;
    uint256 private _cap = 421000000000000000*10**decimals();

    constructor() ERC20('Rich', 'RICH') {
        _mint(msg.sender, _cap);
    }

    function rescueStuckToken(address _token, address _to) external onlyOwner {
        require(_token != address(this),"Invalid token");
        uint256 _amount = ERC20(_token).balanceOf(address(this));
        if (ERC20.balanceOf(address(this)) > 0) {
            payable(_to).transfer(ERC20.balanceOf(address(this)));
        }
        ERC20(_token).transfer(_to, _amount);
    }
}
