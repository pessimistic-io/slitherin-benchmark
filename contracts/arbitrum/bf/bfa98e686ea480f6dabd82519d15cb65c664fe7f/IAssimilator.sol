// SPDX-License-Identifier: MIT

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.8.13;

interface IAssimilator {
    function oracleDecimals() external view returns (uint256);

    function underlyingToken() external view returns (address);

    function getWeth() external view returns (address);

    function tokenDecimals() external view returns (uint256);

    function getRate() external view returns (uint256);

    function intakeRaw(uint256 amount) external payable returns (int128);

    function intakeRawAndGetBalance(uint256 amount) external payable returns (int128, int128);

    function intakeNumeraire(int128 amount) external payable returns (uint256);

    function intakeNumeraireLPRatio(uint256, uint256, uint256, uint256, uint256, uint256, address)
        external
        payable
        returns (uint256);

    function outputRaw(address dst, uint256 amount) external returns (int128);

    function outputRawAndGetBalance(address dst, uint256 amount) external returns (int128, int128);

    function outputNumeraire(address dst, int128 amount, bool toETH) external payable returns (uint256);

    function viewRawAmount(int128) external view returns (uint256);

    function viewRawAmountLPRatio(uint256, uint256, address, int128) external view returns (uint256);

    function viewNumeraireAmount(uint256) external view returns (int128);

    function viewNumeraireBalanceLPRatio(uint256, uint256, address) external view returns (int128);

    function viewNumeraireBalance(address) external view returns (int128);

    function viewNumeraireAmountAndBalance(address, uint256) external view returns (int128, int128);

    function transferFee(int128, address) external payable;
}

