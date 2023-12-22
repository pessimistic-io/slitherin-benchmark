// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;
import "./ArbGasInfo.sol";

contract ArbGasOracleDebug {
    ArbGasInfo internal constant ARB_NITRO_ORACLE =
        ArbGasInfo(0x000000000000000000000000000000000000006C);

    function getCurrentTxL1GasFees() public view returns (uint256) {
        return ARB_NITRO_ORACLE.getCurrentTxL1GasFees();
    }

    function getPricesInWei()
        public
        view
        returns (uint, uint, uint, uint, uint, uint)
    {
        return ARB_NITRO_ORACLE.getPricesInWei();
    }
}

