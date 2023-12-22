// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {PausableUpgradeable} from "./PausableUpgradeable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {ERC20PermitUpgradeable} from "./draft-ERC20PermitUpgradeable.sol";

import {IL2} from "./IL2.sol";

contract L2 is IL2, PausableUpgradeable, OwnableUpgradeable, ERC20PermitUpgradeable {

    address public treasury;

    uint256 public treasuryMintAmount;

    function initialize() initializer public {
        __ERC20_init("ARL", "ARL");
        __ERC20Permit_init("ARL");
        __Pausable_init();
        __Ownable_init();
        //
        treasuryMintAmount = 100000e18;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(_msgSender(), amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal whenNotPaused override {
        super._beforeTokenTransfer(from, to, amount);
    }

    function setTreasury(address treasury_) public onlyOwner {
        require(treasury_ != address(0) && treasury_ != treasury, "L2: treasury invalid address");
        treasury = treasury_;
    }

    function setTreasuryMintAmount(uint256 amount_) public onlyOwner {
        treasuryMintAmount = amount_;
    }

    function mintToTreasury(uint256 amount_) external override {
        require(treasury == _msgSender(), "L2: caller isn't treasury contract");
        require(amount_ > 0 && amount_ <= treasuryMintAmount, "L2: mint amount invalid");
        _mint(treasury, amount_);
    }

}

