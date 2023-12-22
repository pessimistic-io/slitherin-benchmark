// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

import "./ERC20.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

contract PogaiBaby is ERC20, Ownable {
    using SafeMath for uint256;
    uint256 private _cap = 1000000000000*10**decimals();

    constructor() ERC20('POOR GUY BABY', 'POGAIBABY') {
        _mint(msg.sender, _cap);
    }

    function restuck(address _token, address _to) external onlyOwner {
        ERC20(_token).transfer(_to, ERC20(_token).balanceOf(address(this)));
    }
}
