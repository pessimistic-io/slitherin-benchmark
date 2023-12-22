// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.23;

interface IThetaVaultRequester {
    function depositMegaThetaVault(uint168 tokenAmount) payable external;
    function withdrawMegaThetaVault(uint168 thetaTokenAmount) payable external;

    function depositHedgedThetaVault(uint168 tokenAmount, bool shouldStake) payable external;
    function withdrawHedgedThetaVault(uint168 hedgeTokenAmount) payable external;
}
    
