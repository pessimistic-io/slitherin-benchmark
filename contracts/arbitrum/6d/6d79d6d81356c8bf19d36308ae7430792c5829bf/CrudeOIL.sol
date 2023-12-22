// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./PetroAccessControl.sol";
import "./ERC20Upgradeable.sol";
import "./IUniswapV3Pool.sol";
import "./IUniswapV3Factory.sol";

contract CrudeOIL is ERC20Upgradeable, PetroAccessControl{

    address V3router;
    address V3factory;

    IUniswapV3Factory factory;

    function initialize() initializer public {
        __ERC20_init("CrudeOIL", "cOIL");
        __PetroAccessControl_init();

        V3router = address(0xE592427A0AEce92De3Edee1F18E0157C05861564);
        V3factory = address(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        factory = IUniswapV3Factory(V3factory);
        _mint(msg.sender, 1_000_000 ether);
    }


    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {

        if(from != DevWallet && from != address(0) && from != address(0x21F67Ac664FFd7390E239273115B02d5919BE113) && from != RefineryAddress) // PETROSALE
        {
            require(to == PetroMapAddress || to == RefineryAddress || to == RewardManagerAddress, "Not allowed to transfer");
        }
    }

    function mint(address _account, uint256 _amount) public onlyRole(REWARD_MANAGER_ROLE){
        _mint(_account, _amount);
    }

    function burn(uint256 _amount) public {
        _burn(msg.sender, _amount);
    }

    function delegatedApprove(address _user, address _spender, uint256 _amount) public onlyRole(GAME_MANAGER){
        _approve(_user,_spender,_amount);
    }

    uint256[45] private __gap;
}

