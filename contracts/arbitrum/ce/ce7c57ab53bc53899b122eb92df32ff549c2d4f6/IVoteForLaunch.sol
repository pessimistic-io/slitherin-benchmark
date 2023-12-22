// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IVoteForLaunch {
    struct Application {
        uint128     totalVotes;
        uint128     deposit;
        address     applicant;
        uint40      expireAt;
        uint40      passedTimestamp;
        bool        passed;
        string      cid;
        bool        deployed;
        uint128     topVotes;
    }
    
    struct Ballot {
        address addr;
        uint128 amount;
    }

    function getApplication(string memory _tick) external view returns(Application memory);
    function getStatus(string memory _tick, address _sender) external view returns(bool result, uint8 code, string memory description);
    function isPassed(string memory _tick, address _sender) external view returns(bool);
    function setDeployedTicks(string memory _tick, uint8 _code) external;
}

