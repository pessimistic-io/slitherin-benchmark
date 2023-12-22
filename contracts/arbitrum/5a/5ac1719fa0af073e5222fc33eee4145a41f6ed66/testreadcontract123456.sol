    pragma solidity ^0.8.0;

    contract testreadcontract123456 {

        function gimmeastring(uint256 a) public pure returns (string memory) {
            if(a == 1) {
                return "Result 1";
            } else {
                return "Result 2";
            }
        }

    }