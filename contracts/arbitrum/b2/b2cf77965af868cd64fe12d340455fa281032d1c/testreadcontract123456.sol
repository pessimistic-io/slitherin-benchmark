pragma solidity ^0.8.0;

    contract testreadcontract123456 {

        int256 public aNumber;

        function gimmeastring(uint256 a) public pure returns (string memory) {
            if(a == 1) {
                return "Result 3";
            } else {
                return "Result 4";
            }
        }

        function storeMeANumber(int a) public {
            aNumber = a;
        }

    }