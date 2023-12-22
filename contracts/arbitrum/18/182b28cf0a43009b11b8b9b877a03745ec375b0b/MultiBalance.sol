// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "./IERC20.sol";

/**
 * Based on Multicall contract (https://github.com/makerdao/multicall).
 */
contract MultiBalance {
    /*
        Check the token balance of a wallet in a token contract
        Returns the balance of the token for user. Avoids possible errors:
        - return 0 on non-contract address 
        - returns 0 if the contract doesn't implement balanceOf
    */
    function tokenBalance(address token) public view returns (uint256) {
        // check if token is actually a contract
        uint256 tokenCode;

        // Disable "assembly usage" finding from Slither. I've reviewed this
        // code and assessed it as safe.
        //
        // slither-disable-next-line assembly
        assembly {
            tokenCode := extcodesize(token)
        } // contract code size

        // is it a contract and does it implement balanceOf
        if (tokenCode > 0) {
            // Disable "calls inside a loop" finding from Slither. It cannot
            // be used for DoS attacks since we use a discrete and catered list
            // of tokens.
            //
            // slither-disable-next-line calls-loop
            return IERC20(token).balanceOf(msg.sender);
        } else {
            return 0;
        }
    }

    /*
    Check the token balances of a wallet for multiple tokens.

    Possible error throws:
        - extremely large arrays for user and or tokens (gas cost too high) 

    Returns a one-dimensional that's user.length * tokens.length long. The
    array is ordered by all of the 0th users token balances, then the 1th
    user, and so on.
    */
    function balances(address[] memory tokens)
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory addrBalances = new uint256[](tokens.length);

        for (uint256 j = 0; j < tokens.length; j++) {
            uint256 addrIdx = j;
            if (tokens[j] != address(0x0)) {
                addrBalances[addrIdx] = tokenBalance(tokens[j]);
            } else {
                addrBalances[addrIdx] = msg.sender.balance; // ETH balance
            }
        }

        return addrBalances;
    }
}

