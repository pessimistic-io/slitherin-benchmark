// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

// imports
import "./OFTV2.sol";
import "./Ownable.sol";

contract MozaicLP is Ownable, OFTV2 {
    address public vault;

    constructor(
        address _layerZeroEndpoint,
        uint8 _sharedDecimals
    ) OFTV2("Mozaic LPToken", "mozLP", _sharedDecimals, _layerZeroEndpoint) {
    }

    modifier onlyVault() {
        require(vault == _msgSender(), "OnlyVault: caller is not the vault");
        _;
    }

    function setVault(address _vault) public onlyOwner {
        require(_vault != address(0) && vault == address(0), "ERROR: Invalid address");
        vault = _vault;
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function mint(address _account, uint256 _amount) public onlyVault {
        _mint(_account, _amount);
    }
    
    function burn(address _account, uint256 _amount) public onlyVault {
        _burn(_account, _amount);
    }
}

