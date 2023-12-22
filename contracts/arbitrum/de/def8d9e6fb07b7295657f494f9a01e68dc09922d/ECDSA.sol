// SPDX-License-Identifier: MIT
// Copyright (c) 2021 TrinityLabDAO
pragma solidity 0.8.7;

import "./ISpaceStorage.sol";

library ECDSA { 
   
    struct SIGNATURES{
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function verify(bytes32 hash, SIGNATURES[] memory signatures, ISpaceStorage _storage) internal view returns (bool) {
        uint confirmations = 0;
        //sig array 
        //1 - owner
        //2 - r
        //3 - s
        //4 - v
        for (uint i=0; i<signatures.length; i++){
           // bytes32 
            if(_storage.validators(ecrecover(hash, signatures[i].v, signatures[i].r, signatures[i].s))){
                confirmations++;
            }
        }
        if(confirmations >= _storage.threshold())
            return true;
        else
            return false;
    }
}
