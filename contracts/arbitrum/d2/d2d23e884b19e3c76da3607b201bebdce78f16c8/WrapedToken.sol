// SPDX-License-Identifier: MIT
// Copyright (c) 2021 TrinityLabDAO
pragma solidity 0.8.7;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";
import "./IWrapedTokenDeployer.sol";

contract WrapedToken is ERC20, ERC20Burnable, Ownable {

    uint256 public origin;
    bytes public origin_hash;
    uint8 immutable _decimals;

    constructor(string memory name, string memory symbol) ERC20(name, symbol){
        (uint256 origin_,  bytes memory origin_hash_, uint8 origin_decimals) = IWrapedTokenDeployer(msg.sender).parameters();
        origin = origin_;
        origin_hash = origin_hash_;
        _decimals = origin_decimals;
    }

    function decimals() public view virtual override returns (uint8){
        return _decimals;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
