// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./OFTV2.sol";

//                                s       .                              
//                               :8      @88>                            
//  .d``                u.      .88      %8P          u.      u.    u.   
//  @8Ne.   .u    ...ue888b    :888ooo    .     ...ue888b   x@88k u@88c. 
//  %8888:u@88N   888R Y888r -*8888888  .@88u   888R Y888r ^"8888""8888" 
//   `888I  888.  888R I888>   8888    ''888E`  888R I888>   8888  888R  
//    888I  888I  888R I888>   8888      888E   888R I888>   8888  888R  
//    888I  888I  888R I888>   8888      888E   888R I888>   8888  888R  
//  uW888L  888' u8888cJ888   .8888Lu=   888E  u8888cJ888    8888  888R  
// '*88888Nu88P   "*888*P"    ^%888*     888&   "*888*P"    "*88*" 8888" 
// ~ '88888F`       'Y"         'Y"      R888"    'Y"         ""   'Y"   
//    888 ^                               ""                             
//    *8E                                                                
//    '8>                                                                
//     "       
contract PotionOFT is OFTV2 {
    constructor(address _layerZeroEndpoint, uint8 _sharedDecimals) OFTV2("POTION", "POTION", _sharedDecimals, _layerZeroEndpoint) {

    }
}

