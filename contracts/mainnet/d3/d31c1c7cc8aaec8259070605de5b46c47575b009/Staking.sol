// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./ERC20.sol";
import "./IERC20.sol";

contract ApeStaking is ERC20 {

    IERC20 public immutable APE;

    event Stake(address indexed recipient, uint256 amountApe, uint256 amountBanana);
    event Unstake(address indexed recipient, uint256 amountApe, uint256 amountBanana);

    constructor(address _ape) ERC20('Staked ApeDAO Token', 'BANANA') {
        require(_ape != address(0));
        APE = IERC20(_ape);
    }

    function apePerBanana() public view returns (uint256) {
      if (totalSupply() == 0) {
        return 1e18;
      } else {
        return (APE.balanceOf(address(this)) * 1e18) / totalSupply();
      }
    }

    function stake(uint256 amountApe) public {
      uint256 amountBanana = (amountApe * 1e18) / apePerBanana();
      require(amountBanana > 0, "ApeStaking: Stake too small");
      APE.transferFrom(msg.sender, address(this), amountApe);
      _mint(msg.sender, amountBanana);
      emit Stake(msg.sender, amountApe, amountBanana);
    }

    function unstake(uint256 amountBanana) public {
      uint256 amountApe = (apePerBanana() * amountBanana) / 1e18;
      require(amountApe > 0, "ApeStaking: Unstake too small");
      _burn(msg.sender, amountBanana);
      APE.transfer(msg.sender, amountApe);
      emit Unstake(msg.sender, amountApe, amountBanana);
    }
}

