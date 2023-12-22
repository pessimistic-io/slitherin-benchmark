// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { OwnerPausable } from "./OwnerPausable.sol";
import { IVault } from "./IVault.sol";

contract TestFaucet is OwnerPausable {
    //
    mapping(address => bool) internal _faucetMap;
    address internal _vault;
    address internal _token;
    uint256 internal _amount;

    function initialize(address vaultArg, address tokenArg, uint256 amountArg) external initializer {
        __OwnerPausable_init();
        _vault = vaultArg;
        _token = tokenArg;
        _amount = amountArg;
        // approve max
        IERC20Upgradeable(_token).approve(_vault, type(uint256).max);
    }

    function getVault() external view returns (address) {
        return _vault;
    }

    function getToken() external view returns (address) {
        return _token;
    }

    function getAmount() external view returns (uint256) {
        return _amount;
    }

    function isFaucet(address to) external view returns (bool) {
        return _faucetMap[to];
    }

    function depositFor(address to) external {
        // TF_EF: existed faucet
        require(!_faucetMap[to], "TF_EF");
        _faucetMap[to] = true;
        IVault(_vault).depositFor(to, _token, _amount);
    }

    function faucet(address to) external {
        // TF_EF: existed faucet
        require(!_faucetMap[to], "TF_EF");
        _faucetMap[to] = true;
        IERC20Upgradeable(_token).transfer(to, _amount);
    }
}

