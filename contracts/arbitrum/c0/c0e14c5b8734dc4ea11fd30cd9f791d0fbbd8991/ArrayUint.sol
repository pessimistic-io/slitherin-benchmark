// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library ArrayUint {

    function removeArrayIndexValue(uint256[] storage array,uint256[1] storage len, uint256 index) internal {
        if (index < array.length){
            for (uint i = index; i<array.length-1; i++){
                array[i] = array[i+1];
            }
            delete array[array.length-1];
            len[0] --;
            //array.length--;
        }

    }


    function removeArrayByValue(uint256[] storage array,uint256[1] storage len, uint256 value) internal {
        if (len[0] > 0){
            for (uint i = 0; i < len[0]; i++){
                if(array[i] == value){
                    removeArrayIndexValue(array,len,i);
                    break;
                }
            }
        }

    }

    function addArrayNewValue(uint256[] storage array,uint256[1] storage len,uint256 value) internal {
        if(array.length == 0 || array.length <= len[0]){
            array.push(value);
            len[0] = array.length;
        }else{
            array[len[0]] = value;
            len[0] ++;
        }
    }


}
