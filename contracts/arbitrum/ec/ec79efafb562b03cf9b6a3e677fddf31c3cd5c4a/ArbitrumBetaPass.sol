// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "./MinterPauserNFT.sol";

/** Created via https://wizard.openzeppelin.com/#erc721 */
contract ArbitrumBetaPass is MinterPauserNFT {
    constructor() MinterPauserNFT("Notional ARB Beta Contest Pass", "ARB_BETA") { }
}

