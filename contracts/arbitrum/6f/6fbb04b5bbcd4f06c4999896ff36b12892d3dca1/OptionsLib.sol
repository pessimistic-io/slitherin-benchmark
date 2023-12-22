pragma solidity 0.8.13;

/**
 *  * SPDX-License-Identifier: GPL-3.0-or-later
 */

import "./Interfaces.sol";
import "./IOptionsVaultFactory.sol";
import "./IOptionsVaultERC20.sol";

library OptionsLib {

    function isTrue(IStructs.BoolState value) internal pure returns (bool){
        return (value==IStructs.BoolState.TrueMutable || value==IStructs.BoolState.TrueImmutable);
    }

    function isFalse(IStructs.BoolState value) internal pure returns (bool){
        return !isTrue(value);
    }

    function isMutable(IStructs.BoolState value) internal pure returns (bool){
        return (value==IStructs.BoolState.TrueMutable || value==IStructs.BoolState.FalseMutable);
    }

    function isImmutable(IStructs.BoolState value) internal pure returns (bool){
        return !isMutable(value);
    }

    function toBoolState(bool value) internal pure returns (IStructs.BoolState){
        if (value)
          return IStructs.BoolState.TrueMutable;
        else
          return IStructs.BoolState.FalseMutable;
    }

    function getStructs(IOptionsVaultFactory factory, address holder, uint256 period, uint256 optionSize, uint256 strike, IStructs.OptionType optionType, uint vaultId, IOracle oracle, address referrer) internal view returns(IStructs.InputParams memory inParams_){

        IStructs.OracleResponse memory o = IStructs.OracleResponse({
            roundId: 0,
            answer: 0,
            startedAt: 0,
            updatedAt: 0,
            answeredInRound: 0
        });

        IStructs.InputParams memory i = IStructs.InputParams({
        holder: holder,
        period: period,
        optionSize: optionSize,
        strike: strike,
        currentPrice: 0,
        optionType: optionType,
        vaultId: vaultId,
        oracle: oracle,
        referrer: referrer,
        vault: IOptionsVaultERC20(address(factory.vaults(vaultId))),
        oracleResponse: o});

        inParams_ = i;
    }

    function isCall(IStructs.OptionType optionType) internal pure returns (bool){
        return optionType == IStructs.OptionType.Call_American || optionType == IStructs.OptionType.Call_European;
    }

    function isPut(IStructs.OptionType optionType) internal pure returns (bool){
        return optionType == IStructs.OptionType.Put_American || optionType == IStructs.OptionType.Put_European;
    }

    function isAmerican(IStructs.OptionType optionType) internal pure returns (bool){
        return optionType == IStructs.OptionType.Call_American || optionType == IStructs.OptionType.Put_American;
    }

    function isEuropean(IStructs.OptionType optionType) internal pure returns (bool){
        return optionType == IStructs.OptionType.Call_European || optionType == IStructs.OptionType.Put_European;
    }

    function isValid(IStructs.OptionType optionType) internal pure returns (bool){
        return isPut(optionType) || isCall(optionType);
    }

}
