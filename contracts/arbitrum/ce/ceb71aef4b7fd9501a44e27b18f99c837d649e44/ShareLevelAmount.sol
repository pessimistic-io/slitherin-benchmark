// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

contract ShareLevelAmount {
    function getShareLevelAmount(uint256 level) public pure returns (uint256) {
        if ( level == 1){
            return 1*1e18;
        } else if ( level == 2){
            return 15*1e18;
        } else if ( level == 3){
            return 50*1e18;
        } else if ( level == 4){
            return 150*1e18;
        } else if ( level == 5){
            return 300*1e18;
        } else if ( level == 6){
            return 500*1e18;
        } else if ( level == 7){
            return 1000*1e18;
        } else if ( level == 8){
            return 1500*1e18;
        } else if ( level == 9){
            return 2000*1e18;
        } else if ( level == 10){
            return 2500*1e18;
        } else if ( level == 11){
            return 3000*1e18;
        } else if ( level == 12){
            return 3500*1e18;
        } else if ( level == 13){
            return 4000*1e18;
        } else if ( level == 14){
            return 4500*1e18;
        }else if ( level == 15){
            return 5000*1e18;
        } else {
            return 0;
        }
    }
}

