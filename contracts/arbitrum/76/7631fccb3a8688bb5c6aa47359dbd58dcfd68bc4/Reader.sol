// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./IERC20.sol";
import "./IOldTokenFarm.sol";

contract Reader {
    IOldTokenFarm private tokenFarm;
    IERC20 private esVela;
    IERC20 private vela;

    constructor(IOldTokenFarm _tokenFarm, IERC20 _vela, IERC20 _esVela) {
        tokenFarm = _tokenFarm;
        esVela = _esVela;
        vela = _vela;
    }

    function getUserOldVelaInfo(address _account) external view returns (uint256, uint256, uint256, uint256, uint256[] memory) {
        IOldTokenFarm.UserInfo memory userVelaInfo = tokenFarm.userInfo(1, _account);
        IOldTokenFarm.UserInfo memory userEsVelaInfo = tokenFarm.userInfo(2, _account);
        uint256[] memory _amounts = new uint256[](2);
        (,,, uint256[] memory _velaPendingAmounts) = tokenFarm.pendingTokens(1, _account);
        (,,, uint256[] memory _esVelaPendingAmounts) = tokenFarm.pendingTokens(2, _account);
        _amounts[0] = _velaPendingAmounts[0];
        _amounts[1] = _esVelaPendingAmounts[0];
        uint256 velaBalance = vela.balanceOf(_account);
        uint256 esVelaBalance = esVela.balanceOf(_account);
        uint256 userVelaStakedAmount = userVelaInfo.amount;
        uint256 userEsVelaStakedAmount = userEsVelaInfo.amount;
        return (velaBalance, esVelaBalance, userVelaStakedAmount, userEsVelaStakedAmount, _amounts);
    }
}

