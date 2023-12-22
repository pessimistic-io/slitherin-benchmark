// SPDX-License-Identifier: MIT

pragma solidity >0.6.6;

import "./BEP20.sol";

contract NativeToken is BEP20 {
    using SafeMath for uint256;
    uint256 public constant maxSupply = 5_000_000e18; // 10_000_000e18 == 10 000 000

    constructor() BEP20('Sky Whales Token', 'SKY') {
        _mint(msg.sender, 300_000e16); // 100_000e16 == 1,000
    }

    /// @notice Creates `_amount` token to token address. Must only be called by the owner (MasterChef).
    function mint(uint256 _amount) public override onlyOwner returns (bool) {
        return mintFor(address(this), _amount);
    }

    function mintFor(address _address, uint256 _amount) public onlyOwner returns (bool) {
        _mint(_address, _amount);
        require(totalSupply() <= maxSupply, "reach max supply");
        return true;
    }

    // Safe sky transfer function, just in case if rounding error causes pool to not have enough sky.
    function safeSkyTransfer(address _to, uint256 _amount) public onlyOwner {
        uint256 skyBal = balanceOf(address(this));
        if (_amount > skyBal) {
            _transfer(address(this), _to, skyBal);
        } else {
            _transfer(address(this), _to, _amount);
        }
    }
}
