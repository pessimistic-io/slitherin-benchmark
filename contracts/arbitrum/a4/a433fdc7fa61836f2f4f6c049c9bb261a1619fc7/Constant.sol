// SPDX-License-Identifier: BUSL-1.1


pragma solidity 0.8.15;

library Constant {

    address public constant ZERO_ADDRESS                        = address(0);
    uint    public constant E18                                 = 1e18;
    uint    public constant PCNT_100                            = 1e18;
    uint    public constant PCNT_50                             = 5e17;
    uint    public constant E12                                 = 1e12;
    
    // SaleTypes
    uint8    public constant TYPE_IDO                            = 0;
    uint8    public constant TYPE_OTC                            = 1;
    uint8    public constant TYPE_NFT                            = 2;

    uint8    public constant PUBLIC                              = 0;
    uint8    public constant STAKER                              = 1;
    uint8    public constant WHITELISTED                         = 2;

    // Register Campaign
    uint    public constant MAX_REBATE_PCNT                     = 5e16; // 5% max   

    // Misc
    bytes public constant ETH_SIGN_PREFIX                       = "\x19Ethereum Signed Message:\n32";

}





