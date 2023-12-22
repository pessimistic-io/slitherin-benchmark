// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";

contract TestToken is ERC20, Ownable {
    uint256 public constant SALE_FEE = 5; // 5%
    address[] private _holders;
    address[] private _routerAddresses;
    address private _distributionContract;
    mapping(address => bool) private _blacklist;

    constructor() ERC20("TestToken", "Test") {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
        addHolder(to);
    }

    function burn(address from, uint256 amount) public onlyOwner {
        _burn(from, amount);
        for (uint256 i = 0; i < _holders.length; i++) {
            if (_holders[i] == from) {
                _holders[i] = _holders[_holders.length - 1];
                _holders.pop();
                break;
            }
        }
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        require(to != address(0), "ERC20: transfer to the zero address");
        require(!_blacklist[_msgSender()], "Address is blacklisted");

        if (isRouterAddress(to)) {
            uint256 fee = (amount * SALE_FEE) / 100;
            _transferWithFee(_msgSender(), to, amount, fee);
            _transfer(address(this), _distributionContract, fee);
        } else {
            _transfer(_msgSender(), to, amount);
        }

        addHolder(to);

        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        require(to != address(0), "ERC20: transfer to the zero address");
        require(!_blacklist[from], "Address is blacklisted");

        if (isRouterAddress(to)) {
            uint256 fee = (amount * SALE_FEE) / 100;
            _transferWithFee(from, to, amount, fee);
            _transfer(address(this), _distributionContract, fee);
        } else {
            _transfer(from, to, amount);
        }

        _approve(from, _msgSender(), allowance(from, _msgSender()) - amount);
        addHolder(to);

        return true;
    }

    function setRouterAddresses(address[] memory addresses) external onlyOwner {
        _routerAddresses = addresses;
    }

    function setDistributionContract(address distributionContract) external onlyOwner {
        _distributionContract = distributionContract;
    }

    function blacklistAddress(address account) external onlyOwner {
        _blacklist[account] = true;
    }

    function removeAddressFromBlacklist(address account) external onlyOwner {
        _blacklist[account] = false;
    }

    function isRouterAddress(address routerAddress) public view returns (bool) {
        for (uint256 i = 0; i < _routerAddresses.length; i++) {
            if (_routerAddresses[i] == routerAddress) {
                return true;
            }
        }
        return false;
    }

    function holdersCount() external view returns (uint256) {
        return _holders.length;
    }

    function holderAtIndex(uint256 index) external view returns (address) {
        require(index < _holders.length, "Invalid index");
        return _holders[index];
    }

    function _transferWithFee(
        address sender,
        address recipient,
        uint256 amount,
        uint256 fee
    ) internal {
        _transfer(sender, address(this), fee); // Transfer the fee to the contract
        _transfer(sender, recipient, amount - fee); // Transfer the remaining amount to the recipient
    }

    function addHolder(address holder) internal {
        for (uint256 i = 0; i < _holders.length; i++) {
            if (_holders[i] == holder) {
                return;
            }
        }
        _holders.push(holder);
    }
}

