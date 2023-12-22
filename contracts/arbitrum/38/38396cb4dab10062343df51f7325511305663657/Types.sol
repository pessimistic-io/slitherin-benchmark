// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

library Types {

    struct StreamRequest {
        uint256 releaseAmount;
        address recipient;
        uint256 startTime;
        uint256 stopTime;
        uint32 vestingRelease;
        uint256 releaseFrequency;
        uint8 transferPrivilege;
        uint8 cancelPrivilege;
        address tokenAddress;
    }

    struct Recipient {
        address recipient;
        uint256 releaseAmount;
    }

    struct RecipientResponse {
        uint256 streamId;
        address recipient;
        uint256 releaseAmount;
    }

    struct StreamGeneral {
        address tokenAddress;
        uint256 startTime;
        uint256 stopTime;
        uint32 vestingRelease;
        uint256 releaseFrequency;
        uint8 transferPrivilege;
        uint8 cancelPrivilege;
    }


    struct StreamGeneralResponse {
        address sender;
        address tokenAddress;
        uint256 startTime;
        uint256 stopTime;
        uint32 vestingRelease;
        uint256 releaseFrequency;
        uint8 transferPrivilege;
        uint8 cancelPrivilege;
    }


    struct StreamResponse {
        uint256 streamId;
        address sender;
        address recipient;
        uint256 releaseAmount;
        uint256 startTime;
        uint256 stopTime;
        uint32 vestingRelease;
        uint256 releaseFrequency;
        uint8 transferPrivilege;
        uint8 cancelPrivilege;
        address tokenAddress;
    }

    struct Stream {
        uint256 streamId;
        address sender;
        uint256 releaseAmount;
        uint256 remainingBalance;
        uint256 startTime;
        uint256 stopTime; 
        uint256 vestingAmount;
        uint256 releaseFrequency;
        uint8 transferPrivilege;
        uint8 cancelPrivilege;
        address recipient;
        address tokenAddress;
        uint8 status;
    }

    struct Fee {
        address tokenAddress;
        uint256 fee;
    }

    struct WithdrawFeeAddress {
        address allowAddress;
        uint32 percentage;
    }

    struct AvailableToken {
        address tokenAddress;
        bool exist;
    }

    struct TokenBalance {
        address tokenAddress;
        uint256 balance;
    }

}
