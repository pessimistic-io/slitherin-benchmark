// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IZaynZapV2TakaDAO} from "./IZaynZapV2TakaDAO.sol";
import {IZaynVaultV2TakaDao} from "./IZaynVaultV2TakaDao.sol";

import {LibYieldGenerationStorage} from "./LibYieldGenerationStorage.sol";

library LibYieldGeneration {
    /// @notice This function is used to deposit collateral for yield generation
    /// @param _termId The term id for which the collateral is being deposited
    /// @param _ethAmount The amount of collateral being deposited
    function _depositYG(uint _termId, uint _ethAmount) internal {
        LibYieldGenerationStorage.YieldGeneration storage yield = LibYieldGenerationStorage
            ._yieldStorage()
            .yields[_termId];

        yield.totalDeposit = _ethAmount;
        yield.currentTotalDeposit = _ethAmount;

        address vaultAddress = yield.providerAddresses["ZaynVault"];

        IZaynZapV2TakaDAO(yield.providerAddresses["ZaynZap"]).zapInEth{value: _ethAmount}(
            vaultAddress,
            _termId
        );

        yield.totalShares = IZaynVaultV2TakaDao(vaultAddress).balanceOf(_termId);
    }

    /// @notice This function is used to withdraw collateral from the yield generation protocol
    /// @param _termId The term id for which the collateral is being withdrawn
    /// @param _collateralAmount The amount of collateral being withdrawn
    /// @param _user The user address that is withdrawing the collateral
    function _withdrawYG(
        uint _termId,
        uint256 _collateralAmount,
        address _user
    ) internal returns (uint) {
        LibYieldGenerationStorage.YieldGeneration storage yield = LibYieldGenerationStorage
            ._yieldStorage()
            .yields[_termId];

        uint neededShares = _ethToShares(_collateralAmount, yield.totalShares, yield.totalDeposit);

        yield.withdrawnCollateral[_user] += _collateralAmount;
        yield.currentTotalDeposit -= _collateralAmount;

        address zapAddress = yield.providerAddresses["ZaynZap"];
        address vaultAddress = yield.providerAddresses["ZaynVault"];

        uint withdrawnAmount = IZaynZapV2TakaDAO(zapAddress).zapOutETH(
            vaultAddress,
            neededShares,
            _termId
        );

        uint withdrawnYield = withdrawnAmount - _collateralAmount;
        yield.withdrawnYield[_user] += withdrawnYield;
        yield.availableYield[_user] += withdrawnYield;

        return withdrawnYield;
    }

    function _sharesToEth(
        uint _currentShares,
        uint _totalDeposit,
        uint _totalShares
    ) internal pure returns (uint) {
        if (_totalShares == 0) {
            return 0;
        } else {
            return (_currentShares * _totalDeposit) / _totalShares;
        }
    }

    function _ethToShares(
        uint _collateralAmount,
        uint _totalShares,
        uint _totalDeposit
    ) internal pure returns (uint) {
        if (_totalDeposit == 0) {
            return 0;
        } else {
            return (_collateralAmount * _totalShares) / _totalDeposit;
        }
    }
}

