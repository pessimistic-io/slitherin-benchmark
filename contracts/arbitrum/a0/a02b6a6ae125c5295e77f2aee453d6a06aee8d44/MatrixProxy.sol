// SPDX-License-Identifier: MIT
import "./IERC20.sol";
import "./MatrixVault.sol";
import "./MatrixLpAutoCompoundOptimism.sol";

pragma solidity ^0.8.6;

contract MatrixProxy {
    // returning want, pricePerFullShare, balance, balanceOfUser, allowanceOfUser
    function getInfo(address _userAddress, address _vaultAddress, address _strategy, address _zapAddress) public view returns (IERC20, uint256, uint256, uint256, uint256, uint256) {        
        address _user = _userAddress;
        address _zap = _zapAddress;
        address _vault = _vaultAddress;

        MatrixVault vault = MatrixVault(_vault);


        IERC20 want = vault.want();
        uint256 pricePerFullShare = vault.getPricePerFullShare();
        uint256 balance = vault.balance();
        uint256 balanceOfUser = vault.balanceOf(_user);
        uint256 allowanceOfUser = vault.allowance(_user, _zap);
        uint256 lpAllowance = want.allowance(_user, _vault);

        return (want, pricePerFullShare, balance, balanceOfUser, allowanceOfUser, lpAllowance);
    }
}
