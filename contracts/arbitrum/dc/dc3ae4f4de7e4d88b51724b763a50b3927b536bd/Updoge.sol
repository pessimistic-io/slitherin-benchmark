// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./AccessControl.sol";
import "./draft-ERC20Permit.sol";
import "./Up.sol";

contract Updoge is ERC20, ERC20Burnable, Pausable, Ownable, ERC20Permit {
    // Balancer Vault
    address public vaultAddress = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    uint256 public sellBurnRate = 1 ether;
    uint256 public buyBurnRate = 0.1 ether;
    uint256 public burnedSupply;
    uint256 public buyVolume;
    uint256 public sellVolume;
    mapping(address => bool) public exempt;

    constructor(
        uint256 supply_
    ) ERC20("tUPDOGE", "tUPDOGE") ERC20Permit("tUPDOGE") {
        exempt[msg.sender] = true;
        exempt[address(this)] = true;
        exempt[address(0)] = true;

        _mint(msg.sender, supply_);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        super._afterTokenTransfer(from, to, amount);

        if (to == address(0)) {
            burnedSupply += amount;
        }
    }

    function transfer(
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        return _taxedTransfer(_msgSender(), recipient, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        return _taxedTransfer(from, to, amount);
    }

    function _taxedTransfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        if (exempt[sender] || exempt[recipient]) {
            _transfer(sender, recipient, amount);
            return true;
        }

        if (sender == vaultAddress || recipient == vaultAddress) {
            uint256 burnRate;

            if (sender == vaultAddress) {
                buyVolume += amount;
                burnRate = buyBurnRate;
            } else {
                sellVolume += amount;
                burnRate = sellBurnRate;
            }

            uint256 burn = (amount * burnRate) / 1 ether;
            amount -= burn;
            _transfer(sender, address(this), burn);
            _burn(address(this), burn);
        }

        _transfer(sender, recipient, amount);

        return true;
    }

    function setExempt(address address_, bool exempt_) public onlyOwner {
        exempt[address_] = exempt_;
    }

    function setVaultAddress(address vaultAddress_) public onlyOwner {
        vaultAddress = vaultAddress_;
    }

    function setBuyBurnRate(uint256 buyBurnRate_) public onlyOwner {
        require(buyBurnRate_ <= 1 ether, "Can't be more than 100%");

        buyBurnRate = buyBurnRate_;
    }

    function setSellBurnRate(uint256 sellBurnRate_) public onlyOwner {
        require(sellBurnRate_ <= 1 ether, "Can't be more than 100%");

        sellBurnRate = sellBurnRate_;
    }

    function totalSupply() public view override returns (uint256) {
        // Do not count Vault's balance in totalSupply since liquidity is locked in there
        return (super.totalSupply() - balanceOf(vaultAddress));
    }
}

