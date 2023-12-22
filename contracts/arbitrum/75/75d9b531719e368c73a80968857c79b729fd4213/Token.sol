// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "./ERC20.sol";
import "./Pausable.sol";
import "./Ownable.sol";

contract VHT is Ownable, Pausable, ERC20 {
    uint constant private supplyLimit = 10_000_000 * 10**18;
    uint public P;
    address public USDT;

    constructor(address _usdt) Ownable() Pausable() ERC20("VerotexHASH Token", "VHT") {
        _mint(msg.sender, 500_000 * 10**18);
        _mint(msg.sender, 500_000 * 10**18);
        USDT = _usdt;
        P = 1 * 10**6;
    }

    function mint(uint _amt) external whenNotPaused() {
        IERC20(USDT).transferFrom(msg.sender, address(this), _amt * P / 10**18);
        _mint(msg.sender, _amt);
        require(totalSupply() <= supplyLimit, "supply limit");
    }

    function setP(uint _p) external onlyOwner() {
        P = _p;
    }

    function pause() external onlyOwner() {
        _pause();
    }

    function unpause() external onlyOwner() {
        _unpause();
    }

    function rescue(address _token) external onlyOwner() {
        IERC20(_token).transfer(owner(), IERC20(_token).balanceOf(address(this))-1);
    }

    function rescueETH() external onlyOwner() {
        payable(address(owner())).transfer(address(this).balance);
    }

    receive() payable external { }
}

