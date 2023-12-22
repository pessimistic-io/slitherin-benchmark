// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.19;

import "./IJackpotStorage.sol";
import "./Utils.sol";

abstract contract Jackpot is IJackpotStorage {
    using TransferUtil for address;
    using ProbabilityLib for Probability;

    /**
     * @dev Jackpot was claimed.
     * @param winner An account who claimed the jackpot.
     * @param tokens The jackpot prize tokens.
     * @param amounts The jackpot prize amounts.
     */
    event JackpotClaim(address winner, address[] tokens, uint[] amounts);

    function _claimJackpot(address pool, address target) internal {
        address[] memory tokens = _listJackpots();
        uint[] memory amounts = new uint[](tokens.length);

        for (uint i = 0; i < tokens.length; i ++) {
            address token = tokens[i];
            uint jackpot = _jackpot(token);
            uint share = _jackpotShare().mul(jackpot);
            if (share >= jackpot) {
                continue;
            }
            _addJackpot(token, -int(share));
            amounts[i] = share;
            token.erc20TransferFrom(pool, target, share);
        }

        emit JackpotClaim(target, tokens, amounts);
    }
}
