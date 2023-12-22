// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

library UintSafe{
    uint16 constant MAX_UINT16 = 65535;
    uint32 constant MAX_UINT32 = 4294967295;

    function CastTo16(uint256 _in) public pure returns(uint16){
        if(_in > MAX_UINT16)
            return MAX_UINT16;
        
        return uint16(_in);
    }

    function CastTo32(uint256 _in) public pure returns(uint32){
        if(_in > MAX_UINT32)
            return MAX_UINT32;
        
        return uint32(_in);
    }
}
