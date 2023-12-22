// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./IERC20.sol";
import "./ERC20.sol";
import "./SafeMath.sol";

// The ResearchFacility is full of rewards and cells.
// The longer you stay, the more CELL you end up with when you leave.
// This contract handles swapping to and from xCell <> Cell
contract ResearchFacility is ERC20 {
    using SafeMath for uint256;
    IERC20 public govToken;

    constructor(
      string memory _name,
      string memory _symbol,
      IERC20 _govToken
    ) public ERC20(_name, _symbol) {
        govToken = _govToken;
    }

    function enter(uint256 _amount) public {
        uint256 totalGovernanceToken = govToken.balanceOf(address(this));
        uint256 totalShares = totalSupply();
        if (totalShares == 0 || totalGovernanceToken == 0) {
            _mint(msg.sender, _amount);
        }
        else {
            uint256 what = _amount.mul(totalShares).div(totalGovernanceToken);
            _mint(msg.sender, what);
        }
        govToken.transferFrom(msg.sender, address(this), _amount);
    }

    function leave(uint256 _share) public {
        uint256 totalShares = totalSupply();
        uint256 what =
            _share.mul(govToken.balanceOf(address(this))).div(totalShares);
        _burn(msg.sender, _share);
        govToken.transfer(msg.sender, what);
    }
}
