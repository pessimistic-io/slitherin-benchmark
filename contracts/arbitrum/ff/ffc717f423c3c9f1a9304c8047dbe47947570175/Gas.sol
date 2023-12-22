// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * Contract to allow sponsoring gas
 */

contract GasFluid {
    // ====== Errors ======
    error InsufficientGasBalance();

    // ====== Modifiers ======
    modifier gasless() {
        uint256 startingGas = gasleft();
        // We assume all bytes are non-empty, because an iteration itself would grow the gas too much for it to be worth
        // deducting empty-byte cost
        uint256 intrinsicGasCost = 21000 + (msg.data.length * 16);

        _; // END OF FUNCTION BODY

        uint256 leftGas = gasleft();

        // 2300 for ETH .trasnfer()
        uint256 weiSpent = ((startingGas - leftGas + intrinsicGasCost + 2300) *
            tx.gasprice) + getAdditionalGasCost();

        if (weiSpent > address(this).balance) revert InsufficientGasBalance();

        payable(tx.origin).transfer(weiSpent);
    }

    /**
     * Get additional gas costs that may incurr within a txn
     * useful for L2's
     */

    uint internal constant ARBITRUM_CHAIN_ID = 42161;

    function getAdditionalGasCost()
        internal
        view
        returns (uint256 additionalGas)
    {
        if (block.chainid == ARBITRUM_CHAIN_ID) {
            (, bytes memory res) = 0x000000000000000000000000000000000000006C
                .staticcall(abi.encodeWithSignature("getCurrentTxL1GasFees()"));

            additionalGas = abi.decode(res, (uint256));
        }
    }
}

