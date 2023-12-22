// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "./ERC20.sol";
import "./SafeMath.sol";
import "./Ownable.sol";


contract mintableERC20 is ERC20, Ownable {
    using SafeMath for uint256;



    constructor() ERC20("mERC20", "mERC20") { 
    }

 
    function burn(address _from, uint256 _amount) external onlyOwner  {
        _burn(_from, _amount);
    }

    function mint(address recipient, uint256 _amount) external onlyOwner {
        _mint(recipient, _amount);
    }

    function decimals() public pure override(ERC20) returns (uint8) {
        return 4;
    }

}
