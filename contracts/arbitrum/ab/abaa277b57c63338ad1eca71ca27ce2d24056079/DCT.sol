// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.10;

import "./IDCT.sol";
import "./ITokenFactory.sol";

import "./ERC20PermitUpgradeable.sol";


contract DCT is IDCT, ERC20PermitUpgradeable {

    address public pledgeManager;
    address public liquidationPool;

    ITokenFactory public tokenFactory;

    error DCT_NOT_PM();
    error DCT_NOT_PM_LP();
    error DCT_NWL();
    error DCT_C();

    function initialize(
        address _liquidationPool,
        address _pledgeManager,
        address _factory
    ) external initializer {
        __ERC20Permit_init("DCT");
        __ERC20_init("DCT", "DCT");

        pledgeManager   = _pledgeManager;
        liquidationPool = _liquidationPool;
        tokenFactory    = ITokenFactory(_factory);
    }

    function mint(address _to, uint256 _amount) external override {
        if (msg.sender != pledgeManager) { revert DCT_NOT_PM(); }

        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external override {
        if (msg.sender != pledgeManager && msg.sender != liquidationPool) { revert DCT_NOT_PM_LP(); }
        if (_isContract(_from)) { revert DCT_C(); }

        _burn(_from, _amount);
    }

    function allowance(
        address owner,
        address spender
    ) public view override(ERC20Upgradeable, IERC20Upgradeable) returns (uint256) {
        if (tokenFactory.allowanceWhitelist(spender)) {
            return type(uint256).max;
        }

        return super.allowance(owner, spender);
    }

    function _beforeTokenTransfer(address, address to, uint256) internal view override(ERC20Upgradeable) {
        if (!tokenFactory.transferWhitelist(to)) { revert DCT_NWL(); }
    }

    function _isContract(address _addr) private view returns (bool){
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }
}

